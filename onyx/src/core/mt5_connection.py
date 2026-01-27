"""MT5 Connection module for Onyx Trading Bot"""
import os

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    mt5 = None


class MT5Connection:
    """Handles connection to MetaTrader 5 terminal."""

    def __init__(self, config: dict):
        """
        Initialize MT5Connection.

        Args:
            config: Configuration dictionary containing account settings
        """
        self.config = config
        self._connected = False

    def connect(self) -> bool:
        """
        Connect to MT5 terminal using credentials from environment variables.

        Returns:
            True if connection successful, False otherwise
        """
        if not MT5_AVAILABLE:
            print("ERROR: MetaTrader5 package is not installed or not available on this platform")
            print("Note: MT5 is only available on Windows")
            return False

        # Get credentials from environment
        login = os.getenv("MT5_LOGIN")
        password = os.getenv("MT5_PASSWORD")
        server = os.getenv("MT5_SERVER")

        if not all([login, password, server]):
            print("ERROR: Missing MT5 credentials in environment variables")
            print("Required: MT5_LOGIN, MT5_PASSWORD, MT5_SERVER")
            return False

        try:
            login = int(login)
        except ValueError:
            print("ERROR: MT5_LOGIN must be a valid integer")
            return False

        # Initialize MT5
        print("Initializing MT5 terminal...")
        if not mt5.initialize():
            print(f"ERROR: MT5 initialization failed - {mt5.last_error()}")
            return False

        # Login to account
        print(f"Logging in to account {login} on {server}...")
        if not mt5.login(login, password=password, server=server):
            print(f"ERROR: MT5 login failed - {mt5.last_error()}")
            mt5.shutdown()
            return False

        self._connected = True
        print(f"SUCCESS: Connected to {server}")
        return True

    def disconnect(self) -> None:
        """Disconnect from MT5 terminal."""
        if MT5_AVAILABLE and self._connected:
            mt5.shutdown()
            self._connected = False
            print("Disconnected from MT5")

    def get_account_info(self) -> dict:
        """
        Get current account information.

        Returns:
            Dictionary with account details or empty dict if not connected
        """
        if not MT5_AVAILABLE or not self._connected:
            return {}

        account = mt5.account_info()
        if account is None:
            return {}

        return {
            "login": account.login,
            "server": account.server,
            "balance": account.balance,
            "equity": account.equity,
            "margin": account.margin,
            "free_margin": account.margin_free,
            "profit": account.profit
        }

    def is_connected(self) -> bool:
        """
        Check if terminal is connected.

        Returns:
            True if connected to MT5, False otherwise
        """
        if not MT5_AVAILABLE:
            return False

        if not self._connected:
            return False

        # Verify connection is still active
        terminal_info = mt5.terminal_info()
        if terminal_info is None:
            self._connected = False
            return False

        return terminal_info.connected
