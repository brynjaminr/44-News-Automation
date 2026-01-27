#!/usr/bin/env python3
"""
Onyx Trading Bot - Main Entry Point
Connects to MetaTrader 5 and monitors drawdown for Blue Guardian prop firm accounts.
"""
import os
import sys
import time

import yaml
from dotenv import load_dotenv

from src.core import MT5Connection
from src.safety import DrawdownMonitor


def load_config(config_path: str = "config/settings.yaml") -> dict:
    """Load configuration from YAML file."""
    try:
        with open(config_path, "r") as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"ERROR: Config file not found: {config_path}")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"ERROR: Failed to parse config file: {e}")
        sys.exit(1)


def format_status_line(dd_info: dict) -> str:
    """Format a single-line status update."""
    equity = dd_info["current_equity"]
    daily_dd = dd_info["daily_dd_pct"]
    overall_dd = dd_info["overall_dd_pct"]

    # Determine status
    if dd_info["daily_dd_halt"] or dd_info["overall_dd_halt"]:
        status = "HALT"
    elif dd_info["daily_dd_warning"] or dd_info["overall_dd_warning"]:
        status = "WARNING"
    else:
        status = "OK"

    return f"Equity: ${equity:,.2f} | Daily DD: {daily_dd:.2f}% | Overall DD: {overall_dd:.2f}% | Status: {status}"


def main():
    """Main entry point for Onyx Trading Bot."""
    print("=" * 60)
    print("ONYX Trading Bot - Blue Guardian Instant Funding")
    print("=" * 60)
    print()

    # Load environment variables from .env file
    load_dotenv()

    # Load configuration
    config = load_config()
    print(f"Loaded config for {config['account']['broker']} - {config['account']['account_type']}")
    print()

    # Create MT5 connection
    mt5_conn = MT5Connection(config)

    # Attempt to connect
    if not mt5_conn.connect():
        print()
        print("Failed to connect to MT5. Please check:")
        print("  1. MT5 terminal is installed and running")
        print("  2. .env file contains valid credentials")
        print("  3. You are on Windows (MT5 only runs on Windows)")
        sys.exit(1)

    print()

    # Get and display account info
    account_info = mt5_conn.get_account_info()
    if account_info:
        print("Account Information:")
        print(f"  Login:   {account_info['login']}")
        print(f"  Server:  {account_info['server']}")
        print(f"  Balance: ${account_info['balance']:,.2f}")
        print(f"  Equity:  ${account_info['equity']:,.2f}")
        print(f"  Profit:  ${account_info['profit']:,.2f}")
    print()

    # Create drawdown monitor
    initial_balance = config["account"]["initial_balance"]
    dd_monitor = DrawdownMonitor(initial_balance, config)

    # Reset daily equity to current value
    dd_monitor.reset_daily()
    print()

    # Display risk thresholds
    risk = config["risk"]
    print("Risk Thresholds:")
    print(f"  Daily DD Warning:   {risk['daily_dd_warning_pct']}%")
    print(f"  Daily DD Halt:      {risk['daily_dd_halt_pct']}%")
    print(f"  Overall DD Warning: {risk['overall_dd_warning_pct']}%")
    print(f"  Overall DD Halt:    {risk['overall_dd_halt_pct']}%")
    print()

    print("Starting drawdown monitor (Ctrl+C to exit)...")
    print("-" * 60)

    try:
        while True:
            # Check if still connected
            if not mt5_conn.is_connected():
                print("\nERROR: Lost connection to MT5")
                break

            # Check drawdown
            dd_info = dd_monitor.check_drawdown()

            # Print status line (overwrite previous line)
            status_line = format_status_line(dd_info)
            print(f"\r{status_line}", end="", flush=True)

            # Check for warning conditions
            if dd_info["daily_dd_warning"] and not dd_info["daily_dd_halt"]:
                print(f"\n*** WARNING: Daily drawdown at {dd_info['daily_dd_pct']:.2f}% ***")

            if dd_info["overall_dd_warning"] and not dd_info["overall_dd_halt"]:
                print(f"\n*** WARNING: Overall drawdown at {dd_info['overall_dd_pct']:.2f}% ***")

            # Check for halt conditions
            if dd_info["daily_dd_halt"]:
                print(f"\n!!! HALT: Daily drawdown limit reached ({dd_info['daily_dd_pct']:.2f}%) !!!")
                print("Trading should be stopped immediately!")
                break

            if dd_info["overall_dd_halt"]:
                print(f"\n!!! HALT: Overall drawdown limit reached ({dd_info['overall_dd_pct']:.2f}%) !!!")
                print("Trading should be stopped immediately!")
                break

            # Wait 1 second before next check
            time.sleep(1)

    except KeyboardInterrupt:
        print("\n")
        print("Received shutdown signal...")

    finally:
        # Clean disconnect
        print("Shutting down...")
        mt5_conn.disconnect()
        print("Onyx Trading Bot stopped.")


if __name__ == "__main__":
    main()
