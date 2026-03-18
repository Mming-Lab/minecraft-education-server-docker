"""
Minecraft Bedrock Edition level.dat の experiments.gametest を有効化するスクリプト。
（Bedrock little-endian NBT / 8バイトヘッダー形式）

使用方法:
    python enable_beta_apis.py <level.datのパス>
"""

import struct
import shutil
import sys
from pathlib import Path

# ─── NBT タグ定数 ───
TAG_END        = 0
TAG_BYTE       = 1
TAG_SHORT      = 2
TAG_INT        = 3
TAG_LONG       = 4
TAG_FLOAT      = 5
TAG_DOUBLE     = 6
TAG_BYTE_ARRAY = 7
TAG_STRING     = 8
TAG_LIST       = 9
TAG_COMPOUND   = 10
TAG_INT_ARRAY  = 11
TAG_LONG_ARRAY = 12


# ─── デシリアライズ ───

def read_string(data: bytes, pos: int) -> tuple[str, int]:
    """2バイト LE 長 + UTF-8 文字列を読む"""
    length, = struct.unpack_from('<H', data, pos)
    pos += 2
    s = data[pos:pos + length].decode('utf-8')
    return s, pos + length


def read_payload(data: bytes, pos: int, tag_type: int):
    """指定タグの値を読んで (value, new_pos) を返す。
    COMPOUND は {name: (tag_type, value)} の dict として表現する。
    LIST は {'_type': int, '_items': list} として表現する。
    """
    if tag_type == TAG_BYTE:
        v, = struct.unpack_from('<b', data, pos)
        return v, pos + 1

    elif tag_type == TAG_SHORT:
        v, = struct.unpack_from('<h', data, pos)
        return v, pos + 2

    elif tag_type == TAG_INT:
        v, = struct.unpack_from('<i', data, pos)
        return v, pos + 4

    elif tag_type == TAG_LONG:
        v, = struct.unpack_from('<q', data, pos)
        return v, pos + 8

    elif tag_type == TAG_FLOAT:
        v, = struct.unpack_from('<f', data, pos)
        return v, pos + 4

    elif tag_type == TAG_DOUBLE:
        v, = struct.unpack_from('<d', data, pos)
        return v, pos + 8

    elif tag_type == TAG_BYTE_ARRAY:
        n, = struct.unpack_from('<i', data, pos); pos += 4
        return list(data[pos:pos + n]), pos + n

    elif tag_type == TAG_STRING:
        return read_string(data, pos)

    elif tag_type == TAG_LIST:
        elem_type = data[pos]; pos += 1
        count, = struct.unpack_from('<i', data, pos); pos += 4
        items = []
        for _ in range(count):
            v, pos = read_payload(data, pos, elem_type)
            items.append(v)
        return {'_type': elem_type, '_items': items}, pos

    elif tag_type == TAG_COMPOUND:
        tags = {}
        while True:
            t = data[pos]; pos += 1
            if t == TAG_END:
                break
            name, pos = read_string(data, pos)
            value, pos = read_payload(data, pos, t)
            tags[name] = (t, value)
        return tags, pos

    elif tag_type == TAG_INT_ARRAY:
        n, = struct.unpack_from('<i', data, pos); pos += 4
        items = [struct.unpack_from('<i', data, pos + i * 4)[0] for i in range(n)]
        return items, pos + n * 4

    elif tag_type == TAG_LONG_ARRAY:
        n, = struct.unpack_from('<i', data, pos); pos += 4
        items = [struct.unpack_from('<q', data, pos + i * 8)[0] for i in range(n)]
        return items, pos + n * 8

    else:
        raise ValueError(f"未知のタグタイプ: {tag_type}")


# ─── シリアライズ ───

def write_string(s: str) -> bytes:
    """2バイト LE 長 + UTF-8 文字列を書く"""
    encoded = s.encode('utf-8')
    return struct.pack('<H', len(encoded)) + encoded


def write_payload(tag_type: int, value) -> bytes:
    """指定タグの値をシリアライズして bytes を返す"""
    if tag_type == TAG_BYTE:
        return struct.pack('<b', value)

    elif tag_type == TAG_SHORT:
        return struct.pack('<h', value)

    elif tag_type == TAG_INT:
        return struct.pack('<i', value)

    elif tag_type == TAG_LONG:
        return struct.pack('<q', value)

    elif tag_type == TAG_FLOAT:
        return struct.pack('<f', value)

    elif tag_type == TAG_DOUBLE:
        return struct.pack('<d', value)

    elif tag_type == TAG_BYTE_ARRAY:
        return struct.pack('<i', len(value)) + bytes(b & 0xFF for b in value)

    elif tag_type == TAG_STRING:
        return write_string(value)

    elif tag_type == TAG_LIST:
        elem_type = value['_type']
        items = value['_items']
        result = struct.pack('<B', elem_type) + struct.pack('<i', len(items))
        for item in items:
            result += write_payload(elem_type, item)
        return result

    elif tag_type == TAG_COMPOUND:
        result = b''
        for name, (t, v) in value.items():
            result += struct.pack('<B', t) + write_string(name) + write_payload(t, v)
        result += struct.pack('<B', TAG_END)
        return result

    elif tag_type == TAG_INT_ARRAY:
        return struct.pack('<i', len(value)) + b''.join(struct.pack('<i', v) for v in value)

    elif tag_type == TAG_LONG_ARRAY:
        return struct.pack('<i', len(value)) + b''.join(struct.pack('<q', v) for v in value)

    else:
        raise ValueError(f"未知のタグタイプ: {tag_type}")


# ─── メイン処理 ───

def main():
    if len(sys.argv) < 2:
        print("使用方法: python enable_beta_apis.py <level.datのパス>")
        sys.exit(1)
    level_dat = Path(sys.argv[1])

    if not level_dat.exists():
        print(f"エラー: {level_dat} が見つかりません")
        sys.exit(1)

    # バックアップ作成
    backup = level_dat.with_suffix('.dat.bak')
    if not backup.exists():
        shutil.copy2(level_dat, backup)
        print(f"バックアップ作成: {backup}")
    else:
        print(f"バックアップ既存: {backup}")

    raw = level_dat.read_bytes()
    print(f"ファイルサイズ: {len(raw)} バイト")

    # ─── ヘッダー読み取り ───
    # version(uint32 LE) + nbt_length(uint32 LE)
    version, nbt_length = struct.unpack_from('<II', raw, 0)
    print(f"ヘッダー: version={version}, nbt_length={nbt_length} (実際={len(raw)-8})")

    nbt_data = raw[8:]

    # ─── ルート compound 読み取り ───
    pos = 0
    root_type = nbt_data[pos]; pos += 1
    if root_type != TAG_COMPOUND:
        raise ValueError(f"ルートタグが COMPOUND ではありません: {root_type}")

    root_name, pos = read_string(nbt_data, pos)
    root_value, pos = read_payload(nbt_data, pos, TAG_COMPOUND)
    print(f"ルートタグ名: '{root_name}' (通常は空文字列)")
    print(f"トップレベルキー数: {len(root_value)}")

    # ─── experiments を確認・更新 ───
    if 'experiments' in root_value:
        _, exp_value = root_value['experiments']
        print(f"既存の experiments:")
        for k, (t, v) in exp_value.items():
            print(f"  {k} = {v}")
    else:
        exp_value = {}
        print("experiments が存在しないため新規作成します")

    # Beta APIs を有効化
    exp_value['experiments_ever_used']         = (TAG_BYTE, 1)
    exp_value['saved_with_toggled_experiments'] = (TAG_BYTE, 1)
    exp_value['gametest']                       = (TAG_BYTE, 1)  # = "Beta APIs"

    root_value['experiments'] = (TAG_COMPOUND, exp_value)

    print(f"\n設定後の experiments:")
    for k, (t, v) in exp_value.items():
        print(f"  {k} = {v}")

    # ─── シリアライズ ───
    new_nbt = struct.pack('<B', TAG_COMPOUND)
    new_nbt += write_string(root_name)
    new_nbt += write_payload(TAG_COMPOUND, root_value)

    # ヘッダー更新（nbt_length = NBT データサイズ）
    new_header = struct.pack('<II', version, len(new_nbt))
    new_raw = new_header + new_nbt

    level_dat.write_bytes(new_raw)
    print(f"\n保存完了: {level_dat}")
    print(f"サイズ: {len(raw)} → {len(new_raw)} バイト (差分: {len(new_raw)-len(raw):+d})")


if __name__ == '__main__':
    main()
