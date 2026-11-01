#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_repo.py —— 把一个装 .deb 的目录变成越狱源（APT repository）。

用法：
    python3 tools/make_repo.py --dir repo

目录约定（--dir 指向的就是 GitHub Pages 的发布根目录）：
    repo/
    ├── debs/            # 放 .deb（可多版本共存）
    ├── Packages         # 生成
    ├── Packages.gz      # 生成
    ├── Packages.xz      # 生成
    └── Release          # 生成

生成的 Packages 里 Filename 是相对仓库根的路径（debs/xxx.deb），
Sileo / Zebra / Cydia 会拼上源地址去下载。

只依赖 Python 标准库：自己解析 ar + tar 拿 control，不要求装 dpkg-dev。
"""

import argparse
import gzip
import hashlib
import io
import lzma
import os
import struct
import sys
import tarfile
import time

# ---------------------------------------------------------------- .deb 解析

def _iter_ar_members(fp):
    magic = fp.read(8)
    if magic != b"!<arch>\n":
        raise ValueError("不是 ar 归档")
    while True:
        hdr = fp.read(60)
        if len(hdr) < 60:
            return
        name = hdr[0:16].decode("ascii", "replace").strip()
        size = int(hdr[48:58].decode("ascii").strip())
        data = fp.read(size)
        if size % 2:
            fp.read(1)
        yield name, data


def read_control(deb_path):
    """返回 (control 文本, data.tar 成员列表大小统计)。"""
    with open(deb_path, "rb") as fp:
        for name, data in _iter_ar_members(fp):
            if name.startswith("control.tar"):
                if name.endswith(".gz"):
                    raw = gzip.decompress(data)
                elif name.endswith(".xz") or name.endswith(".lzma"):
                    raw = lzma.decompress(data)
                elif name.endswith(".zst"):
                    import zstandard  # 可选依赖，只在遇到 zstd 控制包时需要
                    raw = zstandard.ZstdDecompressor().decompress(data)
                else:
                    raw = data
                with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
                    for m in tar.getmembers():
                        base = os.path.basename(m.name)
                        if base in ("control", "./control"):
                            f = tar.extractfile(m)
                            if f:
                                return f.read().decode("utf-8", "replace")
    raise ValueError("deb 里找不到 control")


def control_to_stanza(text):
    """把 control 文本整理成单条 stanza 的行列表（去掉空行、末尾空行）。"""
    lines = [ln.rstrip() for ln in text.replace("\r\n", "\n").split("\n")]
    out = []
    for ln in lines:
        if not ln.strip():
            continue
        out.append(ln)
    return out


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------- 索引生成

def build_packages(repo_dir):
    debs_dir = os.path.join(repo_dir, "debs")
    if not os.path.isdir(debs_dir):
        sys.exit("!! 找不到 %s" % debs_dir)

    stanzas = []
    names = sorted(f for f in os.listdir(debs_dir) if f.endswith(".deb"))
    if not names:
        sys.exit("!! %s 里没有 .deb" % debs_dir)

    for fn in names:
        path = os.path.join(debs_dir, fn)
        text = read_control(path)
        lines = control_to_stanza(text)

        # 去掉 deb 里可能已有的 Filename/Size/SHA256，避免重复字段
        drop = ("Filename:", "Size:", "SHA256:", "MD5sum:", "MD5Sum:")
        lines = [ln for ln in lines if not ln.startswith(drop)]

        lines.append("Filename: debs/%s" % fn)
        lines.append("Size: %d" % os.path.getsize(path))
        lines.append("SHA256: %s" % sha256_of(path))
        lines.append("MD5sum: %s" % md5_of(path))

        pkg = next((ln.split(":", 1)[1].strip() for ln in lines
                    if ln.startswith("Package:")), fn)
        ver = next((ln.split(":", 1)[1].strip() for ln in lines
                    if ln.startswith("Version:")), "?")
        print("  + %-40s %s" % (pkg, ver))
        stanzas.append("\n".join(lines))

    return ("\n\n".join(stanzas) + "\n").encode("utf-8")


def write_release(repo_dir, packages_bytes, meta):
    # 生成三个变体，Sileo 会挑它支持的那个
    variants = [("Packages", packages_bytes)]
    variants.append(("Packages.gz", gzip.compress(packages_bytes, mtime=0)))
    variants.append(("Packages.xz", lzma.compress(packages_bytes, format=lzma.FORMAT_XZ)))

    for name, data in variants:
        with open(os.path.join(repo_dir, name), "wb") as fp:
            fp.write(data)

    md5_lines, sha_lines = [], []
    for name, data in variants:
        md5_lines.append(" %s %d %s" % (hashlib.md5(data).hexdigest(), len(data), name))
        sha_lines.append(" %s %d %s" % (hashlib.sha256(data).hexdigest(), len(data), name))

    release = []
    release.append("Origin: %s" % meta["origin"])
    release.append("Label: %s" % meta["label"])
    release.append("Suite: stable")
    release.append("Version: 1.0")
    release.append("Codename: ios")
    release.append("Architectures: iphoneos-arm64e iphoneos-arm64 iphoneos-arm")
    release.append("Components: main")
    release.append("Description: %s" % meta["description"])
    release.append("Date: %s" % time.strftime("%a, %d %b %Y %H:%M:%S UTC", time.gmtime()))
    release.append("MD5Sum:")
    release.extend(md5_lines)
    release.append("SHA256:")
    release.extend(sha_lines)
    text = "\n".join(release) + "\n"

    with open(os.path.join(repo_dir, "Release"), "w", encoding="utf-8", newline="\n") as fp:
        fp.write(text)

    return text


def main():
    ap = argparse.ArgumentParser(description="把 debs/ 目录打包成越狱源索引")
    ap.add_argument("--dir", default="repo", help="仓库根目录（默认 repo）")
    ap.add_argument("--origin", default="Chenlin8023 Repo")
    ap.add_argument("--label", default="Chenlin8023")
    ap.add_argument("--description", default="iOS 17 tweak 修复与增强 (RootHide / roothide)")
    args = ap.parse_args()

    repo_dir = args.dir
    print("== 扫描 %s/debs ==" % repo_dir)
    packages = build_packages(repo_dir)
    print("== 生成 Packages / Packages.gz / Packages.xz / Release ==")
    write_release(repo_dir, packages, {
        "origin": args.origin,
        "label": args.label,
        "description": args.description,
    })
    print("完成。仓库根目录：%s" % os.path.abspath(repo_dir))
    print("源地址（GitHub Pages）：https://<user>.github.io/<repo>/")


if __name__ == "__main__":
    main()
