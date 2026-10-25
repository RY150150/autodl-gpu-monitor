#!/usr/bin/env python3
"""Watch AutoDL for a selected instance configuration."""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright


TARGET_URL = "https://www.autodl.com/create"
INSTANCE_URL = "https://www.autodl.com/console/instance/list"
RECEIPT_PREFIX = "AUTODL_RECEIPT "
DATA_DIRECTORY = (
    Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local"))
    if os.name == "nt" else Path.home() / "Library/Application Support"
) / "AutoDLMonitor"
DEFAULT_RECEIPT_LOG = DATA_DIRECTORY / "rental-history.jsonl"


def log(message):
    print(f"[{datetime.now().astimezone().isoformat(timespec='seconds')}] {message}", flush=True)


def wait_until_next_poll(started_at, interval):
    remaining = interval - (time.monotonic() - started_at)
    if remaining > 0:
        time.sleep(remaining)


def gpu_count(text):
    """Parse the availability cell shown as e.g. '0 / 8' or '2/8'."""
    match = re.search(r"(?<!\d)(\d+)\s*/\s*(\d+)(?!\d)", text)
    return int(match.group(1)) if match else 0


def hourly_price(text):
    matches = re.findall(
        r"(?:[¥￥]\s*(\d+(?:\.\d+)?)\s*(?:/|每)?\s*(?:小时|时|h)|"
        r"(\d+(?:\.\d+)?)\s*元\s*(?:/|每)?\s*(?:小时|时|h))",
        text,
        re.I,
    )
    values = [float(a or b) for a, b in matches]
    return min(values) if values else None


def price_for_billing(text, billing_mode):
    unit = {
        "按量计费": r"(?:小时|时|h)",
        "包日": r"(?:天|日)",
        "包周": r"(?:周)",
        "包月": r"(?:月)",
    }[billing_mode]
    matches = re.findall(
        rf"(?:[¥￥]\s*(\d+(?:\.\d+)?)\s*(?:/|每)?\s*{unit}|"
        rf"(\d+(?:\.\d+)?)\s*元\s*(?:/|每)?\s*{unit})",
        text,
        re.I,
    )
    values = [float(a or b) for a, b in matches]
    return max(values) if values else None


def selected_control(page, role, name):
    if role == "checkbox":
        pattern = rf"^{re.escape(name)}(?:\s+\(|\s*$)"
    else:
        pattern = rf"^{name}(?:\s+.*)?$"
    controls = page.get_by_role(role, name=re.compile(pattern, re.I)).all()
    for control in controls:
        selected = control.evaluate(
            """el => {
                if (el instanceof HTMLInputElement) return el.checked;
                const checked = el.getAttribute('aria-checked');
                if (checked !== null) return checked === 'true';
                return el.matches('.is-checked, .is-active') ||
                    Boolean(el.querySelector('input:checked'));
            }"""
        )
        if selected:
            return True
    return False


def target_configuration_selected(page, args):
    if not selected_control(page, "radio", args.billing_mode):
        return False, f"{args.billing_mode} 未选中"
    if not selected_control(page, "radio", args.region):
        return False, f"{args.region} 未选中"
    if not selected_control(page, "checkbox", args.gpu_model):
        return False, f"{args.gpu_model} 未勾选"
    if not selected_control(page, "radio", args.gpu_count):
        return False, f"{args.gpu_count} 卡未选中"
    if not selected_control(page, "radio", args.image_type):
        return False, f"{args.image_type} 未选中"
    image_fields = page.get_by_role("textbox").all()
    if not any(
        field.evaluate(
            "(el, expected) => (el.value || el.textContent || '').trim().toLowerCase() === expected.toLowerCase()",
            args.image_name,
        )
        for field in image_fields
    ):
        return False, f"镜像不是 {args.image_name}"
    return True, ""


def ensure_selected(page, role, name):
    if selected_control(page, role, name):
        return True
    if role == "checkbox":
        labels = page.locator(".el-checkbox").filter(
            has_text=re.compile(rf"^{re.escape(name)}(?:\s+\(|\s*$)", re.I)
        ).all()
        for label in labels:
            if label.is_visible():
                label.click()
                page.wait_for_timeout(500)
                if selected_control(page, role, name):
                    return True
        return False

    pattern = rf"^{name}(?:\s+.*)?$"
    controls = page.get_by_role(role, name=re.compile(pattern, re.I)).all()
    for control in controls:
        if control.is_visible():
            control.click()
            page.wait_for_timeout(500)
            if selected_control(page, role, name):
                return True
    return False


def configure_target(page, args):
    required = (
        ("radio", args.billing_mode),
        ("radio", args.region),
        ("checkbox", args.gpu_model),
        ("radio", args.gpu_count),
        ("radio", args.image_type),
    )
    for role, name in required:
        if not ensure_selected(page, role, name):
            return False, f"{name} 无法选中"

    fields = page.get_by_role("textbox").all()
    if any(
        field.evaluate(
            "(el, expected) => (el.value || el.textContent || '').trim().toLowerCase() === expected.toLowerCase()",
            args.image_name,
        )
        for field in fields
    ):
        return True, ""
    if not fields:
        return False, "找不到镜像选择框"

    fields[0].click()
    page.wait_for_timeout(300)
    options = page.get_by_text(args.image_name, exact=True).all()
    for option in reversed(options):
        if option.is_visible():
            option.click()
            page.wait_for_timeout(500)
            return target_configuration_selected(page, args)
    return False, f"镜像列表中找不到 {args.image_name}"


def displayed_config_price(text, billing_mode):
    unit = {
        "按量计费": r"(?:小时|时|h)",
        "包日": r"(?:天|日)",
        "包周": r"(?:周)",
        "包月": r"(?:月)",
    }[billing_mode]
    match = re.search(
        rf"配置费用[：:]?\s*[¥￥]\s*(\d+(?:\.\d+)?)\s*(?:/|每)?\s*{unit}",
        text,
        re.I,
    )
    return float(match.group(1)) if match else None


def target_rows(page, gpu_model, required_count):
    rows = page.locator("tr")
    found = []
    for index in range(rows.count()):
        row = rows.nth(index)
        text = " ".join(row.inner_text().split())
        has_model = re.search(
            rf"(?<![A-Za-z0-9_-]){re.escape(gpu_model)}(?![A-Za-z0-9_-])",
            text,
            re.I,
        )
        if has_model and gpu_count(text) >= required_count:
            found.append((row, text))
    return found


def select_row(row):
    radio = row.locator('input[type="radio"], [role="radio"]').first
    if radio.count():
        radio.click()
        return True
    row.click()
    return True


def write_receipt(path, receipt):
    payload = json.dumps(receipt, ensure_ascii=False)
    try:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a", encoding="utf-8") as output:
            output.write(payload + "\n")
            output.flush()
            os.fsync(output.fileno())
    except OSError as error:
        log(f"租用日志未能保存到本机：{error.strerror or '文件访问失败'}。")
    print(RECEIPT_PREFIX + payload, flush=True)


def parse_instance_cells(cells):
    if len(cells) < 6:
        return None
    match = re.search(r"(?<![A-Za-z0-9])([a-zA-Z0-9]{8,32}-[a-zA-Z0-9]{6,32})(?![A-Za-z0-9])", cells[0])
    if not match:
        return None
    return {
        "instance_id": match.group(1),
        "identity": " ".join(cells[0].split()),
        "state": " ".join(cells[1].split()),
        "spec": " ".join(cells[2].split()),
        "billing": cells[5].strip(),
    }


def instance_snapshot(page):
    # Receipt data is restricted to instance identity, state, GPU spec and billing.
    page.wait_for_function(
        "() => /共\\s*\\d+\\s*条/.test(document.body.innerText)",
        timeout=6000,
    )
    total = re.search(r"共\s*(\d+)\s*条", page.locator("body").inner_text(timeout=6000))
    instances = {}
    for row in page.locator("tr").all():
        columns = row.locator("td")
        if columns.count() < 6:
            continue
        cells = [""] * 6
        for index in (0, 1, 2, 5):
            cells[index] = columns.nth(index).inner_text(timeout=2000)
        item = parse_instance_cells(cells)
        if item:
            instances[item["instance_id"]] = item
    if total is None or len(instances) != int(total.group(1)):
        return None
    return instances


def matching_new_instance(before, after, receipt):
    if before is None or after is None or not receipt["host_label"]:
        return None
    matches = []
    for instance_id, item in after.items():
        if instance_id in before:
            continue
        host = re.match(
            re.escape(receipt["region"]) + r"\s*/\s*" +
            re.escape(receipt["host_label"]) + r"(?!\d)", item["identity"],
        )
        spec = re.match(
            re.escape(receipt["gpu_model"]) + r"\s*[*×]\s*" +
            re.escape(receipt["gpu_count"]) + r"\s*卡(?:\s|查看详情|$)", item["spec"], re.I,
        )
        if receipt["region"] in item["identity"] and host and spec and item["billing"] == receipt["billing_mode"]:
            matches.append(item)
    return matches[0] if len(matches) == 1 else None


def confirm_receipt(page, before, receipt, timeout=30):
    if page is None or before is None:
        return "unconfirmed", None
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            page.reload(wait_until="domcontentloaded", timeout=6000)
            item = matching_new_instance(before, instance_snapshot(page), receipt)
            if item:
                if re.search(r"失败|错误", item["state"]):
                    return "failed", item
                if re.search(r"运行中|已关机|创建中|开机中|启动中", item["state"]):
                    return "confirmed", item
        except PlaywrightError:
            pass
        page.wait_for_timeout(2000)
    return "unconfirmed", None


def submit_and_log(page, action, host_text, args, config_price):
    host = re.search(r"(?<!\d)\d+机", host_text)
    receipt = {
        "order_id": str(uuid4()),
        "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
        "status": "submitted",
        "region": args.region,
        "gpu_model": args.gpu_model,
        "gpu_count": args.gpu_count,
        "billing_mode": args.billing_mode,
        "image_type": args.image_type,
        "image_name": args.image_name,
        "config_price": config_price,
        "host_label": host.group(0) if host else "",
        "instance_id": None,
        "message": "订单已提交，等待实例列表确认。",
    }
    audit_page = None
    before = None
    try:
        audit_page = page.context.new_page()
        audit_page.goto(INSTANCE_URL, wait_until="domcontentloaded", timeout=6000)
        before = instance_snapshot(audit_page)
    except PlaywrightError:
        log("实例列表快照无法完整读取；提交后若无法核验将标记为结果待确认。")

    try:
        configured, _ = target_configuration_selected(page, args)
        current_price = displayed_config_price(" ".join(page.locator("body").inner_text().split()), args.billing_mode)
        if not configured or current_price is None or current_price > args.max_hourly_price:
            log("提交前再次核验配置或价格未通过；本轮不会下单。")
            return False
        receipt["config_price"] = current_price
        try:
            action.click()
        except PlaywrightError:
            receipt.update(status="unconfirmed", message="提交操作未返回明确结果，请检查 AutoDL；不会自动重试下单。")
            write_receipt(args.receipt_log, receipt)
            log(receipt["message"])
            return True
        log("已点击“创建并开机”提交租赁，正在确认创建结果；不会重复下单。")
        write_receipt(args.receipt_log, receipt)
        status, instance = confirm_receipt(audit_page, before, receipt)
        messages = {
            "confirmed": "租用成功：实例列表已确认新增匹配实例。",
            "unconfirmed": "结果待确认：尚未核实到新实例，请在 AutoDL 检查；不会重复下单。",
            "failed": "创建失败：实例列表显示失败或错误，请在 AutoDL 检查。",
        }
        receipt.update(
            status=status, message=messages[status],
            timestamp=datetime.now().astimezone().isoformat(timespec="seconds"),
            instance_id=instance["instance_id"] if instance else None,
        )
        write_receipt(args.receipt_log, receipt)
        log(receipt["message"])
        return True
    except Exception:
        receipt.update(status="unconfirmed", message="创建结果核验中断，请在 AutoDL 检查；不会重复下单。")
        write_receipt(args.receipt_log, receipt)
        log(receipt["message"])
        return True
    finally:
        if audit_page is not None:
            try:
                audit_page.close()
            except PlaywrightError:
                pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cdp", default="http://127.0.0.1:9222", help="Chrome remote-debugging URL")
    parser.add_argument("--interval", type=int, default=5, help="Polling interval in seconds (default: 5)")
    parser.add_argument(
        "--max-hourly-price",
        type=float,
        default=3.0,
        help="Maximum allowed price in the selected billing period (default: 3.00)",
    )
    parser.add_argument("--billing-mode", choices=("按量计费", "包日", "包周", "包月"), default="按量计费")
    parser.add_argument(
        "--region",
        choices=("西北B区", "北京B区", "重庆A区", "内蒙B区", "北京A区", "佛山区", "V100专区", "A800专区", "摩尔线程专区"),
        default="内蒙B区",
    )
    parser.add_argument(
        "--gpu-model",
        choices=(
            "vGPU-32GB", "RTX 5090", "RTX PRO 6000", "RTX 6000D",
            "PRO 6000 Max-Q", "vGPU-48GB", "RTX 5090 D", "RTX PRO 5000",
            "H800", "RTX 4090D", "RTX 4090", "RTX 3090", "RTX 3080 Ti",
            "RTX 3080x2", "RTX A4000", "RTX 3060", "GTX 1080 Ti", "CPU",
            "CPU-close-HT", "vGPU-48GB-350W"
        ),
        default="RTX 4090",
    )
    parser.add_argument("--gpu-count", choices=("1", "2", "3", "4", "5", "6", "7", "8", "10", "12"), default="1")
    parser.add_argument("--image-type", choices=("基础镜像", "社区镜像", "我的镜像"), default="我的镜像")
    parser.add_argument("--image-name", required=True, help="Exact name of an image available in your account")
    parser.add_argument("--receipt-log", type=Path, default=DEFAULT_RECEIPT_LOG, help="Local rental receipt JSONL file")
    parser.add_argument(
        "--monitor-only",
        action="store_true",
        help="Only report availability; do not submit a rent action",
    )
    parser.add_argument("--once", action="store_true", help="Check once and exit")
    args = parser.parse_args()

    if args.max_hourly_price <= 0:
        parser.error("--max-hourly-price must be positive")
    args.image_name = args.image_name.strip()
    if not args.image_name:
        parser.error("--image-name must not be empty")
    auto_rent = not args.monitor_only

    with sync_playwright() as playwright:
        try:
            browser = playwright.chromium.connect_over_cdp(args.cdp)
        except PlaywrightError as error:
            log(f"无法连接 Chrome 调试端口 {args.cdp}。")
            log('请先用 README 中的命令启动专用 Chrome，再登录 AutoDL。')
            log(str(error).splitlines()[0])
            return 2
        context = browser.contexts[0]
        page = next((p for p in context.pages if "autodl.com/create" in p.url), None)
        if page is None:
            page = context.new_page()
            page.goto(TARGET_URL, wait_until="domcontentloaded")
        log("已连接浏览器；仅在核验目标配置、空闲GPU和价格后才尝试创建一台实例。")

        while True:
            cycle_started = time.monotonic()
            try:
                page.reload(wait_until="domcontentloaded", timeout=60000)
                page.wait_for_timeout(2500)
                if "/login" in page.url:
                    log("专用 Chrome 尚未登录 AutoDL，请在该窗口完成登录后重新运行脚本。")
                    if args.once:
                        break
                    wait_until_next_poll(cycle_started, args.interval)
                    continue
                body = " ".join(page.locator("body").inner_text().split())

                configured, reason = configure_target(page, args)
                if not configured:
                    log(f"筛选/镜像设置失败：{reason}。本轮不会下单。")
                else:
                    matches = target_rows(page, args.gpu_model, int(args.gpu_count))
                    if not matches:
                        log(f"当前没有可用的 {args.gpu_model}（满足 {args.gpu_count} 卡）。")
                    else:
                        row, text = matches[0]
                        log(f"发现候选主机：{text}")
                        if not auto_rent:
                            log("只监控模式：未提交订单。")
                        else:
                            price = price_for_billing(text, args.billing_mode)
                            if price is None or price > args.max_hourly_price:
                                log(f"未下单：无法从该主机行核实所选计费周期的价格，或价格超过上限 {args.max_hourly_price:.2f}。")
                            elif "验证码" in body or "captcha" in body.lower():
                                log("检测到验证码，停止自动操作，不尝试绕过。")
                            else:
                                select_row(row)
                                page.wait_for_timeout(1200)
                                detail = " ".join(page.locator("body").inner_text().split())
                                configured, reason = target_configuration_selected(page, args)
                                config_price = displayed_config_price(detail, args.billing_mode)
                                if not configured:
                                    log(f"选中主机后筛选/镜像核验失败：{reason}；停止下单。")
                                elif config_price is None or config_price > args.max_hourly_price:
                                    log(
                                        "未下单：配置费用无法核实，或超过上限 "
                                        f"{args.max_hourly_price:.2f}（所选计费周期）。"
                                    )
                                elif "验证码" in detail or "captcha" in detail.lower():
                                    log("检测到验证码，停止自动操作，不尝试绕过。")
                                else:
                                    action = page.get_by_role(
                                        "button",
                                        name=re.compile(r"^创建并开机$"),
                                    ).last
                                    if not action.count() or not action.is_visible():
                                        log("未找到“创建并开机”按钮，停止下单。")
                                    else:
                                        if submit_and_log(page, action, text, args, config_price):
                                            break
                if args.once:
                    break
                wait_until_next_poll(cycle_started, args.interval)
            except PlaywrightTimeoutError as error:
                log(f"页面响应超时，将继续监控：{error}")
                if args.once:
                    break
                wait_until_next_poll(cycle_started, args.interval)
            except KeyboardInterrupt:
                log("已停止监控。")
                break


if __name__ == "__main__":
    if sys.stdout is not None:
        sys.stdout.reconfigure(encoding="utf-8")
    main()
