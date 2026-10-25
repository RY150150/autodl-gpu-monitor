import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("watch", ROOT / "src/autodl_watch.py")
watch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(watch)


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.receipt = {"region": "内蒙B区", "host_label": "203机", "gpu_model": "RTX 4090", "gpu_count": "1", "billing_mode": "按量计费"}
        self.item = watch.parse_instance_cells([
            "内蒙B区 / 203机 example0001-instance01设置名称", "运行中",
            "RTX 4090 * 1卡查看详情", "", "", "按量计费",
        ])
        self.after = {self.item["instance_id"]: self.item}

    def test_availability(self):
        self.assertEqual(watch.gpu_count("2 / 8"), 2)
        self.assertEqual(watch.gpu_count("unknown"), 0)

    def test_price_units(self):
        self.assertEqual(watch.displayed_config_price("配置费用： ￥2.18 /时", "按量计费"), 2.18)
        self.assertIsNone(watch.displayed_config_price("配置费用： ￥2.18 /时", "包月"))

    def test_image_name_required(self):
        result = subprocess.run([sys.executable, str(ROOT / "src/autodl_watch.py"), "--once", "--monitor-only"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("--image-name", result.stderr)

    def test_empty_image_rejected(self):
        result = subprocess.run([sys.executable, str(ROOT / "src/autodl_watch.py"), "--image-name", "  ", "--monitor-only"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("must not be empty", result.stderr)

    def test_instance_parser(self):
        self.assertEqual(self.item["instance_id"], "example0001-instance01")
        self.assertIsNone(watch.parse_instance_cells(["header"]))

    def test_new_instance_required(self):
        self.assertEqual(watch.matching_new_instance({}, self.after, self.receipt), self.item)
        self.assertIsNone(watch.matching_new_instance(self.after, self.after, self.receipt))
        self.assertIsNone(watch.matching_new_instance(None, self.after, self.receipt))

    def test_similar_gpu_is_not_selected(self):
        wrong = dict(self.item, spec="RTX 4090D * 1卡")
        self.assertIsNone(watch.matching_new_instance({}, {wrong["instance_id"]: wrong}, self.receipt))

    def test_wrong_host_is_not_selected(self):
        wrong = dict(self.item, identity="内蒙B区 / 1203机")
        self.assertIsNone(watch.matching_new_instance({}, {wrong["instance_id"]: wrong}, self.receipt))

    def test_ambiguous_instances_are_not_success(self):
        after = dict(self.after, second=dict(self.item, instance_id="second"))
        self.assertIsNone(watch.matching_new_instance({}, after, self.receipt))

    def test_confirmation(self):
        for state, expected in (("运行中", "confirmed"), ("创建失败", "failed")):
            item = dict(self.item, state=state)
            with patch.object(watch, "instance_snapshot", return_value={item["instance_id"]: item}):
                self.assertEqual(watch.confirm_receipt(MagicMock(), {}, self.receipt)[0], expected)
        self.assertEqual(watch.confirm_receipt(MagicMock(), {}, self.receipt, timeout=0)[0], "unconfirmed")

    def test_submit_is_never_retried(self):
        with tempfile.TemporaryDirectory() as folder:
            args = SimpleNamespace(
                region="内蒙B区", gpu_model="RTX 4090", gpu_count="1",
                billing_mode="按量计费", image_type="我的镜像", image_name="my-training-image",
                receipt_log=Path(folder) / "receipts.jsonl", max_hourly_price=3,
            )
            page, action = MagicMock(), MagicMock()
            page.locator.return_value.inner_text.return_value = "配置费用： ￥2.18 /时"
            with patch.object(watch, "target_configuration_selected", return_value=(True, "")), patch.object(
                watch, "instance_snapshot", return_value={}
            ), patch.object(watch, "confirm_receipt", return_value=("confirmed", self.item)), contextlib.redirect_stdout(io.StringIO()):
                watch.submit_and_log(page, action, "203机 RTX 4090", args, 2.18)
            action.click.assert_called_once()
            records = [json.loads(line) for line in args.receipt_log.read_text(encoding="utf-8").splitlines()]
            self.assertEqual([row["status"] for row in records], ["submitted", "confirmed"])
            self.assertEqual(records[0]["order_id"], records[1]["order_id"])

    def test_click_timeout_is_not_success(self):
        with tempfile.TemporaryDirectory() as folder:
            args = SimpleNamespace(
                region="内蒙B区", gpu_model="RTX 4090", gpu_count="1",
                billing_mode="按量计费", image_type="我的镜像", image_name="my-training-image",
                receipt_log=Path(folder) / "receipts.jsonl", max_hourly_price=3,
            )
            page, action = MagicMock(), MagicMock()
            page.locator.return_value.inner_text.return_value = "配置费用： ￥2.18 /时"
            action.click.side_effect = watch.PlaywrightTimeoutError("simulated timeout")
            with patch.object(watch, "target_configuration_selected", return_value=(True, "")), patch.object(
                watch, "instance_snapshot", return_value={}
            ), contextlib.redirect_stdout(io.StringIO()):
                watch.submit_and_log(page, action, "203机", args, 2.18)
            action.click.assert_called_once()
            self.assertEqual(json.loads(args.receipt_log.read_text(encoding="utf-8"))["status"], "unconfirmed")


if __name__ == "__main__":
    unittest.main()
