"""Drawdown Monitor module for 44TradingBot"""

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    MT5_AVAILABLE = False
    mt5 = None


class DrawdownMonitor:
    """Monitors account drawdown and enforces risk limits."""

    def __init__(self, initial_balance: float, config: dict):
        """
        Initialize DrawdownMonitor.

        Args:
            initial_balance: Starting balance for overall DD calculation
            config: Configuration dictionary containing risk thresholds
        """
        self.initial_balance = initial_balance
        self.daily_start_equity = initial_balance

        # Load risk thresholds from config
        risk_config = config.get("risk", {})
        self.daily_dd_warning_pct = risk_config.get("daily_dd_warning_pct", 1.2)
        self.daily_dd_halt_pct = risk_config.get("daily_dd_halt_pct", 1.7)
        self.overall_dd_warning_pct = risk_config.get("overall_dd_warning_pct", 4.0)
        self.overall_dd_halt_pct = risk_config.get("overall_dd_halt_pct", 5.0)

    def _get_current_equity(self) -> float:
        """Get current equity from MT5."""
        if not MT5_AVAILABLE:
            return self.initial_balance

        account = mt5.account_info()
        if account is None:
            return self.daily_start_equity

        return account.equity

    def reset_daily(self) -> None:
        """Reset daily equity tracking to current equity."""
        self.daily_start_equity = self._get_current_equity()
        print(f"Daily equity reset to: ${self.daily_start_equity:,.2f}")

    def check_drawdown(self) -> dict:
        """
        Check current drawdown levels against thresholds.

        Returns:
            Dictionary with drawdown metrics and status flags
        """
        current_equity = self._get_current_equity()

        # Calculate daily drawdown percentage
        if self.daily_start_equity > 0:
            daily_dd_pct = ((self.daily_start_equity - current_equity) / self.daily_start_equity) * 100
        else:
            daily_dd_pct = 0.0

        # Calculate overall drawdown percentage
        if self.initial_balance > 0:
            overall_dd_pct = ((self.initial_balance - current_equity) / self.initial_balance) * 100
        else:
            overall_dd_pct = 0.0

        # Check warning thresholds
        daily_dd_warning = daily_dd_pct >= self.daily_dd_warning_pct
        overall_dd_warning = overall_dd_pct >= self.overall_dd_warning_pct

        # Check halt thresholds
        daily_dd_halt = daily_dd_pct >= self.daily_dd_halt_pct
        overall_dd_halt = overall_dd_pct >= self.overall_dd_halt_pct

        # Can only trade if neither halt condition is triggered
        can_trade = not (daily_dd_halt or overall_dd_halt)

        return {
            "current_equity": current_equity,
            "daily_start_equity": self.daily_start_equity,
            "initial_balance": self.initial_balance,
            "daily_dd_pct": daily_dd_pct,
            "daily_dd_warning": daily_dd_warning,
            "daily_dd_halt": daily_dd_halt,
            "overall_dd_pct": overall_dd_pct,
            "overall_dd_warning": overall_dd_warning,
            "overall_dd_halt": overall_dd_halt,
            "can_trade": can_trade
        }
