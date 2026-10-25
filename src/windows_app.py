"""Secondary Windows edition. Not tested on a real Windows desktop."""

import json
import math
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import messagebox, ttk


REGIONS = ["西北B区", "北京B区", "重庆A区", "内蒙B区", "北京A区", "佛山区", "V100专区", "A800专区", "摩尔线程专区"]
GPUS = [
    "vGPU-32GB", "RTX 5090", "RTX PRO 6000", "RTX 6000D", "PRO 6000 Max-Q",
    "vGPU-48GB", "RTX 5090 D", "RTX PRO 5000", "H800", "RTX 4090D", "RTX 4090",
    "RTX 3090", "RTX 3080 Ti", "RTX 3080x2", "RTX A4000", "RTX 3060",
    "GTX 1080 Ti", "CPU", "CPU-close-HT", "vGPU-48GB-350W",
]
DATA_DIR = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "AutoDLMonitor"
RECEIPT_LOG = DATA_DIR / "rental-history.jsonl"


def find_chrome():
    candidates = [shutil.which("chrome")]
    for variable in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"):
        root = os.environ.get(variable)
        if root:
            candidates.append(str(Path(root) / "Google/Chrome/Application/chrome.exe"))
    return next((path for path in candidates if path and Path(path).is_file()), None)


class MonitorApp:
    def __init__(self, root):
        self.root = root
        self.worker = None
        self.launch_timer = None
        self.events = queue.Queue()
        self.order_status = None
        self.inputs = []
        root.title("AutoDL 算力监控 · Windows 次要版 · 未实机测试")
        root.geometry("940x790")
        root.minsize(840, 720)
        root.configure(background="#FAFBFA")
        root.protocol("WM_DELETE_WINDOW", self.close)
        style = ttk.Style(root)
        style.theme_use("clam")
        style.configure(".", font=("Segoe UI", 10), background="#FAFBFA", foreground="#202B26")
        style.configure("Title.TLabel", font=("Segoe UI", 23, "bold"))
        style.configure("Warning.TLabel", foreground="#8A5400", background="#FFF3D6", padding=10)
        style.configure("Primary.TButton", foreground="white", background="#237858", padding=(18, 10))
        style.map("Primary.TButton", background=[("active", "#1B6347"), ("disabled", "#BFCBC4")])
        style.configure("TButton", padding=(14, 10))
        style.configure("TCombobox", padding=6, fieldbackground="white")
        style.configure("Treeview", rowheight=28)
        panel = ttk.Frame(root, padding=26)
        panel.pack(fill="both", expand=True)
        header = ttk.Frame(panel)
        header.pack(fill="x")
        ttk.Label(header, text="AutoDL", style="Title.TLabel").pack(side="left")
        self.status = tk.StringVar(value="已停止")
        ttk.Label(header, textvariable=self.status).pack(side="right")
        ttk.Label(
            panel, text="Windows 次要版本 · 尚未经过 Windows 实机测试",
            style="Warning.TLabel",
        ).pack(fill="x", pady=(12, 18))
        self.values = {}
        grid = ttk.Frame(panel)
        grid.pack(fill="x")
        grid.columnconfigure(1, weight=1, uniform="fields")
        grid.columnconfigure(3, weight=1, uniform="fields")
        fields = [
            ("地区", "region", REGIONS, "内蒙B区"),
            ("GPU 型号", "gpu-model", GPUS, "RTX 4090"),
            ("计费方式", "billing-mode", ["按量计费", "包日", "包周", "包月"], "按量计费"),
            ("GPU 数量", "gpu-count", ["1", "2", "3", "4", "5", "6", "7", "8", "10", "12"], "1"),
            ("镜像类型", "image-type", ["基础镜像", "社区镜像", "我的镜像"], "我的镜像"),
            ("镜像名称", "image-name", None, ""),
        ]
        for index, (label, name, choices, default) in enumerate(fields):
            row, column = divmod(index, 2)
            column *= 2
            ttk.Label(grid, text=label).grid(row=row, column=column, sticky="w", padx=(0, 12), pady=12)
            variable = tk.StringVar(value=default)
            self.values[name] = variable
            control = ttk.Combobox(grid, textvariable=variable, values=choices, state="readonly") if choices else ttk.Entry(grid, textvariable=variable)
            control.grid(row=row, column=column + 1, sticky="ew", padx=(0, 22 if column == 0 else 0), pady=12)
            self.inputs.append((control, "readonly" if choices else "normal"))
        policy = ttk.Frame(panel)
        policy.pack(fill="x", pady=(18, 16))
        ttk.Label(policy, text="最高价格").pack(side="left")
        self.price = tk.StringVar(value="3.00")
        price_entry = ttk.Entry(policy, textvariable=self.price, width=12)
        price_entry.pack(side="left", padx=12)
        self.inputs.append((price_entry, "normal"))
        self.price_unit = tk.StringVar(value="元/小时")
        ttk.Label(policy, textvariable=self.price_unit).pack(side="left")
        self.values["billing-mode"].trace_add("write", self.update_price_unit)
        self.auto_rent = tk.BooleanVar(value=True)
        toggle = ttk.Checkbutton(policy, text="发现后自动租赁一台", variable=self.auto_rent)
        toggle.pack(side="right")
        self.inputs.append((toggle, "normal"))
        ttk.Separator(panel).pack(fill="x")
        actions = ttk.Frame(panel)
        actions.pack(fill="x", pady=18)
        ttk.Label(actions, text="轮询周期 5 秒 · 订单上限 1 台").pack(side="left")
        self.start_button = ttk.Button(actions, text="开始监控", style="Primary.TButton", command=self.start)
        self.start_button.pack(side="right")
        self.stop_button = ttk.Button(actions, text="停止", command=self.stop, state="disabled")
        self.stop_button.pack(side="right", padx=10)
        tabs = ttk.Notebook(panel)
        tabs.pack(fill="both", expand=True)
        live = ttk.Frame(tabs)
        history = ttk.Frame(tabs)
        tabs.add(live, text=" 运行日志 ")
        tabs.add(history, text=" 租用日志 ")
        self.log = tk.Text(live, font=("Consolas", 10), wrap="word", borderwidth=0, background="#F1F4F2", foreground="#202B26", padx=14, pady=14)
        self.log.pack(side="left", fill="both", expand=True)
        scroll = ttk.Scrollbar(live, command=self.log.yview)
        scroll.pack(side="right", fill="y")
        self.log.configure(yscrollcommand=scroll.set, state="disabled")
        self.history = ttk.Treeview(history, columns=("time", "status", "config", "instance"), show="headings")
        for column, title, width in [
            ("time", "时间", 175), ("status", "状态", 105),
            ("config", "配置 / 镜像 / 页面报价", 360), ("instance", "实例 ID", 180),
        ]:
            self.history.heading(column, text=title)
            self.history.column(column, width=width, minwidth=80)
        self.history.pack(side="left", fill="both", expand=True)
        history_scroll = ttk.Scrollbar(history, command=self.history.yview)
        history_scroll.pack(side="right", fill="y")
        self.history.configure(yscrollcommand=history_scroll.set)
        self.append("应用已就绪；镜像名称需自行填写。Windows 次要版尚未经过实机测试。")
        self.load_history()
        root.after(100, self.drain_events)

    def update_price_unit(self, *_):
        self.price_unit.set({"按量计费": "元/小时", "包日": "元/天", "包周": "元/周", "包月": "元/月"}[self.values["billing-mode"].get()])

    def set_running(self, running, status):
        self.status.set(status)
        self.start_button.configure(state="disabled" if running else "normal")
        self.stop_button.configure(state="normal" if running else "disabled")
        for control, state in self.inputs:
            control.configure(state="disabled" if running else state)

    def start(self):
        if self.worker is not None or self.launch_timer is not None:
            return
        image = self.values["image-name"].get().strip()
        try:
            price = float(self.price.get())
            if not math.isfinite(price) or price <= 0:
                raise ValueError()
        except ValueError:
            messagebox.showerror("价格无效", "请输入有效且大于 0 的价格上限。")
            return
        if not image:
            messagebox.showerror("镜像名称为空", "请填写你自己的镜像名称。")
            return
        chrome = find_chrome()
        if not chrome:
            messagebox.showerror("未找到 Chrome", "请先安装 Google Chrome。")
            return
        self.order_status = None
        self.set_running(True, "正在启动 Chrome…")
        try:
            subprocess.Popen([
                chrome, "--remote-debugging-port=9222",
                "--user-data-dir=" + str(DATA_DIR / "chrome-profile"),
                "https://www.autodl.com/create",
            ])
            self.launch_timer = self.root.after(2000, lambda: self.launch_worker(price, image))
        except OSError as error:
            self.set_running(False, "启动失败")
            self.append(str(error))

    def launch_worker(self, price, image):
        self.launch_timer = None
        if getattr(sys, "frozen", False):
            command = [str(Path(sys.executable).parent / "autodl_watch.exe")]
        else:
            command = [sys.executable, "-u", str(Path(__file__).with_name("autodl_watch.py"))]
        command += ["--interval", "5", "--max-hourly-price", str(price), "--receipt-log", str(RECEIPT_LOG)]
        for name, variable in self.values.items():
            command += ["--" + name, image if name == "image-name" else variable.get()]
        if not self.auto_rent.get():
            command.append("--monitor-only")
        try:
            environment = dict(os.environ, PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
            self.worker = subprocess.Popen(
                command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace", env=environment,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            self.set_running(True, "正在监控，5 秒检查一次")
            self.append("监控已启动；自动租赁：" + ("开启" if self.auto_rent.get() else "关闭"))
            threading.Thread(target=self.read_worker, args=(self.worker,), daemon=True).start()
        except OSError as error:
            self.worker = None
            self.set_running(False, "启动失败")
            self.append(str(error))

    def read_worker(self, worker):
        for line in worker.stdout:
            self.events.put(("line", line.rstrip()))
        self.events.put(("exit", worker.wait()))

    def drain_events(self):
        while True:
            try:
                kind, value = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "exit":
                self.worker = None
                self.load_history()
                self.set_running(False, self.order_status or ("已停止" if value == 0 else "运行结束，请检查日志"))
            elif value.startswith("AUTODL_RECEIPT "):
                try:
                    receipt = json.loads(value[len("AUTODL_RECEIPT "):])
                    self.order_status = self.status_title(receipt.get("status")) + "，监控已停止"
                    self.append(self.status_title(receipt.get("status")) + " · " + receipt.get("message", ""))
                    self.load_history()
                except (ValueError, TypeError):
                    self.append("租用日志事件格式无法读取。")
            else:
                self.append(value)
        self.root.after(100, self.drain_events)

    @staticmethod
    def status_title(status):
        return {"confirmed": "租用成功", "submitted": "订单已提交", "failed": "创建失败"}.get(status, "结果待确认")

    def load_history(self):
        records = {}
        try:
            if RECEIPT_LOG.exists():
                for line in RECEIPT_LOG.read_text(encoding="utf-8").splitlines():
                    try:
                        item = json.loads(line)
                        records[item["order_id"]] = item
                    except (ValueError, KeyError, TypeError):
                        continue
            self.history.delete(*self.history.get_children())
            for item in sorted(records.values(), key=lambda item: item.get("timestamp", ""), reverse=True):
                config = " / ".join(str(item.get(name, "")) for name in ("region", "gpu_model", "gpu_count", "image_name", "config_price", "billing_mode"))
                self.history.insert("", "end", values=(
                    item.get("timestamp", ""), self.status_title(item.get("status")),
                    config, item.get("instance_id") or "未确认",
                ))
        except OSError as error:
            self.append("读取租用日志失败：" + str(error))

    def append(self, message):
        self.log.configure(state="normal")
        self.log.insert("end", message + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def stop(self):
        if self.launch_timer is not None:
            self.root.after_cancel(self.launch_timer)
            self.launch_timer = None
        worker = self.worker
        if worker and worker.poll() is None:
            if os.name == "nt":
                try:
                    result = subprocess.run(
                        ["taskkill", "/PID", str(worker.pid), "/T", "/F"],
                        capture_output=True, timeout=10,
                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                    )
                    if result.returncode != 0 and worker.poll() is None:
                        self.append("未能停止监控进程，请检查任务管理器。")
                except (OSError, subprocess.TimeoutExpired) as error:
                    self.append("停止监控失败：" + str(error))
            else:
                worker.terminate()
            self.append("已请求停止；已提交的订单不会被取消。")
        else:
            self.set_running(False, "已停止")

    def close(self):
        if self.worker is not None and self.worker.poll() is None:
            if not messagebox.askyesno("退出", "退出会停止监控，但不会取消已经提交的订单。确定退出吗？"):
                return
        self.stop()
        if self.worker is not None and self.worker.poll() is None:
            messagebox.showerror("仍在停止", "监控进程尚未停止，请稍后再退出。")
            return
        self.root.destroy()


def main():
    if sys.platform != "win32":
        raise SystemExit("This secondary, untested GUI edition is intended for Windows.")
    root = tk.Tk()
    MonitorApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
