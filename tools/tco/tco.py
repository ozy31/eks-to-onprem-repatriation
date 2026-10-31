#!/usr/bin/env python3
"""Cloud vs. on-prem total cost of ownership, month by month.

    python3 tools/tco/tco.py tools/tco/example.toml
    python3 tools/tco/tco.py tools/tco/example.toml --json

The model is deliberately plain: every number comes from the input file, and
the output shows the monthly run rate of each option, the one-off cost of the
move (including the months both sites run), and the month in which the
cumulative savings pay that back.
"""

from __future__ import annotations

import argparse
import json
import sys
import tomllib
from dataclasses import dataclass, field

HOURS_PER_MONTH = 730


@dataclass
class Cloud:
    monthly: dict[str, float]
    growth_percent_per_year: float = 0.0

    def cost(self, month: int) -> float:
        """Cost of month `month` (0-based), with yearly growth compounded."""
        years = month // 12
        return sum(self.monthly.values()) * (1 + self.growth_percent_per_year / 100) ** years


@dataclass
class OnPrem:
    hardware: list[dict]
    amortization_months: int
    racks: int
    rack_month: float
    kw_per_rack: float
    pue: float
    price_per_kwh: float
    monthly: dict[str, float] = field(default_factory=dict)
    fte: float = 0.0
    fte_month: float = 0.0

    @property
    def capex(self) -> float:
        return sum(item["units"] * item["unit_price"] for item in self.hardware)

    def breakdown(self) -> dict[str, float]:
        power = self.racks * self.kw_per_rack * self.pue * HOURS_PER_MONTH * self.price_per_kwh
        lines = {
            "hardware (amortized)": self.capex / self.amortization_months,
            "colocation": self.racks * self.rack_month,
            "power": power,
            "staff": self.fte * self.fte_month,
        }
        lines.update(self.monthly)
        return lines

    def cost(self, month: int) -> float:
        """Flat over the horizon: the hardware is sized for it up front."""
        del month
        return sum(self.breakdown().values())


@dataclass
class Migration:
    one_off: float
    dual_running_months: int


def load(path: str) -> tuple[Cloud, OnPrem, Migration, int]:
    with open(path, "rb") as f:
        data = tomllib.load(f)
    cloud = Cloud(**data["cloud"])
    onprem = OnPrem(**data["onprem"])
    migration = Migration(**data["migration"])
    validate(onprem, migration)
    return cloud, onprem, migration, int(data.get("horizon_months", 60))


def validate(onprem: OnPrem, migration: Migration) -> None:
    if onprem.amortization_months <= 0:
        raise ValueError("onprem.amortization_months must be positive")
    if onprem.pue < 1:
        raise ValueError("onprem.pue cannot be below 1.0")
    if migration.dual_running_months < 0:
        raise ValueError("migration.dual_running_months cannot be negative")


def simulate(cloud: Cloud, onprem: OnPrem, migration: Migration, horizon: int) -> dict:
    """Cumulative cost of staying in the cloud vs. moving, month by month.

    Moving means: the one-off cost in month 0, both sites paid during the
    dual-running months, on-prem only afterwards.
    """
    stay = move = 0.0
    payback_month = None
    months = []
    for m in range(horizon):
        stay += cloud.cost(m)
        move += onprem.cost(m) + (cloud.cost(m) if m < migration.dual_running_months else 0.0)
        if m == 0:
            move += migration.one_off
        if payback_month is None and move <= stay:
            payback_month = m + 1
        months.append({"month": m + 1, "stay": round(stay, 2), "move": round(move, 2)})

    return {
        "cloud_monthly": round(cloud.cost(0), 2),
        "onprem_monthly": round(onprem.cost(0), 2),
        "onprem_breakdown": {k: round(v, 2) for k, v in onprem.breakdown().items()},
        "capex": round(onprem.capex, 2),
        "one_off": round(migration.one_off + migration.dual_running_months * cloud.cost(0), 2),
        "payback_month": payback_month,
        "horizon_months": horizon,
        "savings_at_horizon": round(stay - move, 2),
        "months": months,
    }


def money(value: float) -> str:
    return f"${value:,.0f}"


def report(result: dict) -> str:
    lines = [
        f"{'Cloud run rate':<34}{money(result['cloud_monthly'])}/month",
        f"{'On-prem run rate':<34}{money(result['onprem_monthly'])}/month",
    ]
    for name, value in result["onprem_breakdown"].items():
        lines.append(f"  {name:<32}{money(value)}")
    lines += [
        f"{'Hardware (capex)':<34}{money(result['capex'])}",
        f"{'Move (one-off + dual running)':<34}{money(result['one_off'])}",
    ]
    if result["payback_month"] is None:
        lines.append(f"No payback within {result['horizon_months']} months")
    else:
        lines.append(f"{'Payback in month':<34}{result['payback_month']}")
    for year in (3, 5):
        month = year * 12
        if month <= result["horizon_months"]:
            row = result["months"][month - 1]
            lines.append(f"{f'{year}-year total':<34}stay {money(row['stay'])}, move {money(row['move'])},"
                         f" difference {money(row['stay'] - row['move'])}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("input", help="TOML file, see example.toml")
    parser.add_argument("--json", action="store_true", help="print the full result as JSON")
    args = parser.parse_args(argv)

    try:
        result = simulate(*load(args.input))
    except (KeyError, TypeError, ValueError) as err:
        print(f"invalid input: {err}", file=sys.stderr)
        return 2

    print(json.dumps(result, indent=2) if args.json else report(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
