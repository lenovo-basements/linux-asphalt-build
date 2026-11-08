import urllib.request, re, os

repos = ["core", "extra"]
patterns = [
    r"iwd-[0-9][^\"'<>]+\.pkg\.tar\.(?:zst|xz)",
    r"ell-[0-9][^\"'<>]+\.pkg\.tar\.(?:zst|xz)",
    r"iw-[0-9][^\"'<>]+\.pkg\.tar\.(?:zst|xz)",
    r"wireless-regdb-[0-9][^\"'<>]+\.pkg\.tar\.(?:zst|xz)",
    r"wpa_supplicant-[0-9][^\"'<>]+\.pkg\.tar\.(?:zst|xz)",
    r"libnl-[0-9][^\"'<>]+\.pkg\.tar\.(?:zst|xz)",
    r"pcsclite-[0-9][^\"'<>]+\.pkg\.tar\.(?:zst|xz)",
]

out_dir = "/tmp/arch-pkgs"
os.makedirs(out_dir, exist_ok=True)

for repo in repos:
    url = f"http://tw2.mirror.archlinuxarm.org/aarch64/{repo}/"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    html = urllib.request.urlopen(req, timeout=10).read().decode("utf-8")
    for pat in patterns:
        matches = re.findall(pat, html)
        if matches:
            pkg_file = sorted(set(matches))[-1]
            dest = os.path.join(out_dir, pkg_file)
            if not os.path.exists(dest):
                pkg_url = url + pkg_file
                print(f"Downloading {pkg_file} from {pkg_url}...")
                urllib.request.urlretrieve(pkg_url, dest)
                print(f"Saved {pkg_file} ({os.path.getsize(dest)} bytes)")
print("Done!")
