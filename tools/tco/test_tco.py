import contextlib
import io
import pathlib
import unittest

import tco

EXAMPLE = pathlib.Path(__file__).with_name("example.toml")


def model(cloud_monthly=100.0, onprem_monthly=60.0, one_off=0.0, dual=0, growth=0.0):
    cloud = tco.Cloud(monthly={"all": cloud_monthly}, growth_percent_per_year=growth)
    onprem = tco.OnPrem(hardware=[], amortization_months=60, racks=0, rack_month=0,
                        kw_per_rack=0, pue=1.0, price_per_kwh=0, monthly={"all": onprem_monthly})
    return cloud, onprem, tco.Migration(one_off=one_off, dual_running_months=dual)


class SimulateTest(unittest.TestCase):
    def test_immediate_payback_without_move_costs(self):
        result = tco.simulate(*model(), horizon=12)
        self.assertEqual(result["payback_month"], 1)
        self.assertEqual(result["savings_at_horizon"], 12 * 40)

    def test_one_off_cost_is_paid_back_by_monthly_savings(self):
        # 40/month savings, 400 to recover: cumulative move <= stay in month 10.
        result = tco.simulate(*model(one_off=400), horizon=24)
        self.assertEqual(result["payback_month"], 10)

    def test_dual_running_counts_both_sites(self):
        # Months 1-2 pay both sites (160/month against 100); from month 3 the
        # move saves 40/month, so the 120 head start is recovered in month 5.
        result = tco.simulate(*model(dual=2), horizon=24)
        self.assertEqual(result["one_off"], 200)
        self.assertEqual(result["payback_month"], 5)

    def test_no_payback_when_onprem_is_more_expensive(self):
        result = tco.simulate(*model(onprem_monthly=120), horizon=24)
        self.assertIsNone(result["payback_month"])
        self.assertLess(result["savings_at_horizon"], 0)

    def test_cloud_growth_compounds_yearly(self):
        cloud, _, _ = model(growth=10)
        self.assertEqual(cloud.cost(11), 100)
        self.assertAlmostEqual(cloud.cost(12), 110)
        self.assertAlmostEqual(cloud.cost(24), 121)


class OnPremTest(unittest.TestCase):
    def test_breakdown(self):
        onprem = tco.OnPrem(hardware=[{"name": "n", "units": 10, "unit_price": 6000}],
                            amortization_months=60, racks=2, rack_month=1000,
                            kw_per_rack=5, pue=1.5, price_per_kwh=0.1, fte=1, fte_month=8000)
        lines = onprem.breakdown()
        self.assertEqual(lines["hardware (amortized)"], 1000)
        self.assertEqual(lines["colocation"], 2000)
        self.assertAlmostEqual(lines["power"], 2 * 5 * 1.5 * 730 * 0.1)
        self.assertEqual(lines["staff"], 8000)

    def test_invalid_pue(self):
        _, onprem, migration = model()
        onprem.pue = 0.9
        with self.assertRaises(ValueError):
            tco.validate(onprem, migration)


class ExampleTest(unittest.TestCase):
    def test_example_file_loads_and_pays_back(self):
        result = tco.simulate(*tco.load(str(EXAMPLE)))
        self.assertGreater(result["cloud_monthly"], result["onprem_monthly"])
        self.assertIsNotNone(result["payback_month"])

    def test_cli(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(tco.main([str(EXAMPLE)]), 0)
        self.assertIn("Payback in month", out.getvalue())


if __name__ == "__main__":
    unittest.main()
