#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
arm64e PAC 后处理（clang19 / ld64 956 构建的 iOS 二进制）。

clang19 生成的 arm64e 切片里有两类指针缺少 PAC 认证，加载即崩：

1. __DATA_CONST,__cfstring 的 isa
   -> 普通 bind，objc_msgSend 遇到常量字符串接收者时 SIGBUS。
   需要改写为 auth bind24：diversity=0x6AE1, addrDiv=1, key=2。

2. __DATA,__objc_data 中每个 class_t 的
      isa       (结构体偏移 0x00)
      superclass(结构体偏移 0x08)
   同 Xcode 产物对比，isa 需要 auth(div=0x6AE1)，superclass 需要
   auth(div=0xB5AB)，addrDiv=1, key=2。缺失时 objc readClass()
   在 map_images 阶段做指针认证会 SIGBUS（设置面板点击即闪退）。

用法：python3 patch_arm64e.py <macho>
arm64 切片不需要处理（无 PAC 语义）；非 FAT/无 arm64e 时直接跳过。
"""
import struct
import sys

CHAINED = 0x80000034
SEGMENT64 = 0x19

ISA_DIV = 0x6AE1
SUPERCLASS_DIV = 0xB5AB
AUTH_KEY = 2          # IA key


def u16(d, o):
    return struct.unpack_from("<H", d, o)[0]


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def u64(d, o):
    return struct.unpack_from("<Q", d, o)[0]


def encode_auth_bind24(ordinal, diversity, next_delta):
    return ((ordinal & 0xFFFFFF)
            | (0 << 24)
            | ((diversity & 0xFFFF) << 32)
            | (1 << 48)          # addrDiv
            | (AUTH_KEY << 49)
            | ((next_delta & 0x7FF) << 51)
            | (1 << 62)          # bind
            | (1 << 63))         # auth


def encode_auth_rebase24(target, diversity, next_delta):
    return ((target & 0xFFFFFFFF)
            | ((diversity & 0xFFFF) << 32)
            | (1 << 48)
            | (AUTH_KEY << 49)
            | ((next_delta & 0x7FF) << 51)
            | (0 << 62)
            | (1 << 63))


def patch_slice(d, off):
    ncmds = u32(d, off + 16)
    q = off + 32
    segs = []
    fixups = None
    for _ in range(ncmds):
        cmd, csz = u32(d, q), u32(d, q + 4)
        if cmd == SEGMENT64:
            name = bytes(d[q + 8:q + 24]).rstrip(b"\0").decode()
            vmaddr = u64(d, q + 24)
            vmsize = u64(d, q + 32)
            fileoff = u64(d, q + 40)
            filesize = u64(d, q + 48)
            nsects = u32(d, q + 64)
            secs = []
            for j in range(nsects):
                b = q + 72 + j * 80
                sname = bytes(d[b:b + 16]).rstrip(b"\0").decode()
                addr = u64(d, b + 32)
                size = u64(d, b + 40)
                soff = u32(d, b + 48)          # slice 内绝对文件偏移
                secs.append((sname, addr, size, off + soff))
            segs.append((name, vmaddr, vmsize, fileoff, filesize, secs))
        elif cmd == CHAINED:
            fixups = u32(d, q + 8)
        q += csz

    if fixups is None:
        return 0, 0

    def section_at(file_offset):
        for name, _vmaddr, _vmsize, _fo, _fs, secs in segs:
            for sname, _addr, size, soff in secs:
                if soff <= file_offset < soff + size:
                    return "%s,%s" % (name, sname), soff
        return None, None

    def vm_to_file(vm_offset):
        for name, vmaddr, vmsize, fo, fs, secs in segs:
            if vmaddr <= vm_offset < vmaddr + vmsize:
                return off + fo + (vm_offset - vmaddr)
        return None

    base = off + fixups
    starts_off = u32(d, base + 4)
    seg_count = u32(d, base + starts_off)

    cf_patched = 0
    objc_patched = 0

    for si in range(seg_count):
        so = u32(d, base + starts_off + 4 + si * 4)
        if so == 0:
            continue
        sbase = base + starts_off + so
        _size, page_size, pointer_format, seg_vmoff, _mv, page_count = \
            struct.unpack_from("<IHHQIH", d, sbase)
        if pointer_format != 12:          # 仅 arm64e (USERLAND24)
            continue
        for p in range(page_count):
            ps = u16(d, sbase + 22 + p * 2)
            if ps == 0xFFFF:
                continue
            if ps & 0x8000:               # multi-start，当前二进制不会出现
                print("  [warn] multi-start page, skipped:", si, p)
                continue
            page_file = vm_to_file(seg_vmoff + p * page_size)
            if page_file is None:
                continue
            cur = page_file + ps
            while True:
                raw = u64(d, cur)
                bind = (raw >> 62) & 1
                auth = (raw >> 63) & 1
                nxt = (raw >> 51) & 0x7FF
                secname, sec_off = section_at(cur)

                if secname and secname.endswith("__cfstring"):
                    if bind and not auth:
                        d[cur:cur + 8] = struct.pack(
                            "<Q", encode_auth_bind24(raw & 0xFFFFFF, ISA_DIV, nxt))
                        cf_patched += 1
                elif secname and secname.endswith("__objc_data"):
                    rel = cur - sec_off
                    if rel % 0x28 == 0:            # class/metaclass isa
                        diversity = ISA_DIV
                    elif rel % 0x28 == 8:          # class/metaclass superclass
                        diversity = SUPERCLASS_DIV
                    else:
                        diversity = None
                    if diversity is not None:
                        if bind:
                            newv = encode_auth_bind24(raw & 0xFFFFFF, diversity, nxt)
                        else:
                            newv = encode_auth_rebase24(raw & 0xFFFFFFFF, diversity, nxt)
                        d[cur:cur + 8] = struct.pack("<Q", newv)
                        objc_patched += 1

                if nxt == 0:
                    break
                cur += 8 * nxt
    return cf_patched, objc_patched


def main(path):
    d = bytearray(open(path, "rb").read())
    if struct.unpack_from(">I", d, 0)[0] != 0xCAFEBABE:
        print("  跳过（不是 FAT）:", path)
        return 0

    total_cf = total_objc = 0
    nfat = struct.unpack_from(">I", d, 4)[0]
    for i in range(nfat):
        ct, sub, off, _sz, _al = struct.unpack_from(">IIIII", d, 8 + i * 20)
        if ct != 0x0100000C or sub != 0x80000002:
            continue
        cf, objc = patch_slice(d, off)
        total_cf += cf
        total_objc += objc
        print("  arm64e: __cfstring isa 改写 %d 条，__objc_data 类指针认证 %d 条"
              % (cf, objc))

    open(path, "wb").write(bytes(d))
    print("  %s: 完成（cfstring=%d, objc_data=%d）"
          % (path.split("/")[-1], total_cf, total_objc))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: patch_arm64e.py <macho>")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
