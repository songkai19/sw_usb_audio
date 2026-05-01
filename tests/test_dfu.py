# Copyright 2015-2026 XMOS LIMITED.
# This Software is subject to the terms of the XMOS Public Licence: Version 1.
from pathlib import Path
import pytest
import re
import subprocess
import platform

from hardware_test_tools.UaDfuApp import UaDfuApp
from conftest import get_firmware_path, AppUsbAudDut, get_xtag_dut


def get_dfu_bin_path(board, config):
    if config:
        return (
            Path(__file__).parents[1]
            / f"app_usb_aud_{board}"
            / "bin"
            / f"{config}"
            / f"app_usb_aud_{board}_{config}.bin"
        )
    else:
        return (
            Path(__file__).parents[1]
            / f"app_usb_aud_{board}"
            / "bin"
            / f"app_usb_aud_{board}.bin"
        )


def create_dfu_bin(board, config):
    firmware_path = get_firmware_path(board, config)
    dfu_bin_path = get_dfu_bin_path(board, config)
    # Assume that XE was built with the same version of XTC Tools as used in this test
    version = xtc_version()
    subprocess.run(
        [
            "xflash",
            "--factory-version",
            f'{version["major"]}.{version["minor"]}',
            "--upgrade",
            "1",
            firmware_path,
            "-o",
            dfu_bin_path,
        ],
        check=True,
    )
    return dfu_bin_path


def xtc_version():
    version_re = r"XTC version: (?P<major>\d+)\.(?P<minor>\d+)\.(?P<patch>\d+)"
    ret = subprocess.run(["xcc", "--version"], capture_output=True, text=True)
    match = re.search(version_re, ret.stdout)
    if not match:
        pytest.fail(f"Unable to get XTC Tools version: stdout={ret.stdout}")
    return match.groupdict()


def check_upload_file(upload_file):
    print("check upload file")
    cmd = f"xflash --analyze {upload_file}".split()
    ret = subprocess.run(cmd, text=True, capture_output=True, timeout=10)
    assert ret.returncode == 0, f"Failed to analyze upload file, is file corrupted, cmd {cmd}\nstdout:\n{ret.stdout}\nstderr:\n{ret.stderr}"


# Test cases are defined by a tuple of (board, initial config to xflash)
dfu_testcases = [
    ("xk_216_mc", "2AMi10o10xssxxx"),
    ("xk_316_mc", "2AMi10o10xssxxx"),
    ("xk_316_mc", "2AMi8o8xxxxxx_winbuiltin"),
    ("xk_316_mc", "1SMi2o2xxxxxx"),
    ("xk_evk_xu316", "2AMi2o2xxxxxx"),
    ("xk_316_mc", "1SMi2o2xxxxxx_old_tools"), # factory image built with older XTC tools to test that we can upgrade from one XTC version to another
    ("template", "")
]


def dfu_uncollect(pytestconfig, board, config, dfuapp):
    # XTAG not present
    xtag_id = get_xtag_dut(pytestconfig, board)
    if not xtag_id:
        return True

    winbuiltin_configs = ["2AMi8o8xxxxxx_winbuiltin", "1SMi2o2xxxxxx", "1SMi2o2xxxxxx_old_tools"] # Configs for which the winbuiltin driver is used on Windows
    if platform.system() == "Windows":
        if (dfuapp == "custom") and (config in winbuiltin_configs): # when testing with Thesycon DFU app, uncollect the winbuiltin config
            return True
    else: # not on Windows
        if config == "2AMi8o8xxxxxx_winbuiltin": # Uncollect the 2AMi8o8xxxxxx_winbuiltin config since it's only built for Windows
            return True

    level = pytestconfig.getoption("level")
    if level == "smoke":
        if platform.system() == "Darwin":
            # Just run on xk_316_mc at smoke level
            return (board not in ["xk_316_mc"]) or (config not in ["2AMi10o10xssxxx"])
        else:
            # Skip DFU for smoke on Windows as tested enough in lib_xua
            return True
    return False

'''
Sequence when testing the template app:
app_usb_aud_template -download-> (xk_316_mc, upgrade1) -download-> app_usb_aud_template -upload-> test_dfu_upload.bin
-revert_factory-> app_usb_aud_template -download-> (xk_316_mc, upgrade1) -download-> test_dfu_upload.bin
-revert_factory

Sequence when testing other apps (eg. xk_316_mc, 2AMi10o10xssxxx):
(xk_316_mc, 2AMi10o10xssxxx) -download-> (xk_316_mc, upgrade1) -download-> (xk_316_mc, upgrade2) -upload-> test_dfu_upload.bin
-revert_factory-> (xk_316_mc, 2AMi10o10xssxxx) -download-> test_dfu_upload.bin
-revert_factory
'''
@pytest.mark.uncollect_if(func=dfu_uncollect)
@pytest.mark.parametrize(["board", "config"], dfu_testcases)
@pytest.mark.parametrize("dfuapp", ["custom", "dfu-util"])
def test_dfu(pytestconfig, board, config, dfuapp):
    adapter_dut = get_xtag_dut(pytestconfig, board)
    writeall = False
    if "old_tools" in config: # For the old_tools test the factory executable has been compiled and converted to a binary file with an older XTC tools version
        writeall = True # In the test we only do xflash --write-all to write the binary file to the device and any xflash version would do at this point

    if "dfu-util" in dfuapp:
        ret = subprocess.run("dfu-util -V".split(), capture_output=True, text=True)
        print(f"dfu-util check: {ret.stdout}")

    with AppUsbAudDut(adapter_dut, board, config, xflash=True, writeall=writeall) as dut:
        dfu_test = UaDfuApp(dut.features["pid"], dfu_app_type=dfuapp)

        initial_version = dfu_test.get_bcd_version()
        if initial_version != "9.20":
            print(f"Unexpected initial version {initial_version}, attempting to revert to factory image before starting test, expected 9.20")
            dfu_test.revert_factory()
            initial_version = dfu_test.get_bcd_version()

        assert initial_version == "9.20", f"Initial version {initial_version} didn't match expected 9.20"

        exp_version1 = "99.01"
        exp_version2 = "99.02"

        # perform the first upgrade
        if "winbuiltin" in config:
            dfu_bin1 = create_dfu_bin(board, "winbuiltin_upgrade1")
        elif "1SM" in config:
            dfu_bin1 = create_dfu_bin(board, "uac1_upgrade1")
        else:
            if board == "template":
                dfu_bin1 = create_dfu_bin("xk_316_mc", "upgrade1")
            else:
                dfu_bin1 = create_dfu_bin(board, "upgrade1")

        dfu_test.download(dfu_bin1)
        version = dfu_test.get_bcd_version()
        assert version == exp_version1, f"Unexpected version {version} after first upgrade doesn't match expected {exp_version1}"

        # perform the second upgrade
        if "winbuiltin" in config:
            dfu_bin2 = create_dfu_bin(board, "winbuiltin_upgrade2")
        elif "1SM" in config:
            dfu_bin2 = create_dfu_bin(board, "uac1_upgrade2")
        else:
            if board == "template": # for template, go back to the app_usb_aud_template so we can test dfu upload for it
                dfu_bin2 = create_dfu_bin(board, "")
                exp_version2 = initial_version
            else:
                dfu_bin2 = create_dfu_bin(board, "upgrade2")

        dfu_test.download(dfu_bin2)
        version = dfu_test.get_bcd_version()
        assert version == exp_version2, f"Unexpected version {version} after second upgrade"

        upload_file = Path(__file__).parent / "test_dfu_upload.bin"
        dfu_test.upload(upload_file)
        version = dfu_test.get_bcd_version()
        assert version == exp_version2, f"Unexpected version {version} after reading upgrade image"

        check_upload_file(upload_file)

        dfu_test.revert_factory()
        version = dfu_test.get_bcd_version()
        assert version == initial_version, f"After factory reset, version {version} didn't match initial {initial_version}"

        # Needed for template app
        # Download (xk_316_mc, upgrade1) first so that when downloading upload_file, a version change can be observed
        if board == "template":
            dfu_test.download(dfu_bin1)
            version = dfu_test.get_bcd_version()
            assert version == exp_version1, f"Unexpected version {version} after first upgrade"

        dfu_test.download(upload_file)
        upload_file.unlink()
        version = dfu_test.get_bcd_version()
        assert version == exp_version2, f"Unexpected version {version} after writing the image that was read"

        # Finish by reverting back to the factory image again
        dfu_test.revert_factory()
        version = dfu_test.get_bcd_version()
        assert version == initial_version, f"Version {version} didn't match initial {initial_version} after final factory reset"
