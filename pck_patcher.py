#!/usr/bin/env python3
"""
ExtraStimulantsPlus PCK Tool
Robust patcher and packer for Godot 4 games.
Handles permanent bootstrap injection and mod distribution.
"""

import struct
import hashlib
import os
import sys
import argparse
import shutil
import zipfile
from typing import Dict, List, Optional, Any

class GodotPCK:
    """Handles low-level Godot 4 PCK file manipulation."""
    
    def __init__(self):
        self.pck_version = 2 # Godot 4
        self.major = 4
        self.minor = 0
        self.patch = 0
        self.files: Dict[str, Dict[str, Any]] = {}
        self.source_pck: Optional[str] = None

    def load(self, filename: str):
        """Reads the PCK index and metadata."""
        if not os.path.exists(filename):
            raise FileNotFoundError(f"PCK file not found: {filename}")
            
        self.source_pck = filename
        with open(filename, 'rb') as f:
            magic = f.read(4)
            if magic != b'GDPC':
                raise ValueError(f"Invalid PCK magic: {magic}. Expected 'GDPC'.")
            
            self.pck_version = struct.unpack('<I', f.read(4))[0]
            self.major = struct.unpack('<I', f.read(4))[0]
            self.minor = struct.unpack('<I', f.read(4))[0]
            self.patch = struct.unpack('<I', f.read(4))[0]
            
            f.read(64) # Skip reserved space
            
            file_count = struct.unpack('<I', f.read(4))[0]
            print(f"Reading PCK index ({file_count} files)...")
            
            for _ in range(file_count):
                path_len = struct.unpack('<I', f.read(4))[0]
                path = f.read(path_len).decode('utf-8').replace('\0', '')
                offset = struct.unpack('<Q', f.read(8))[0]
                size = struct.unpack('<Q', f.read(8))[0]
                md5 = f.read(16)
                
                flags = 0
                if self.pck_version >= 2: # Godot 4+
                    flags = struct.unpack('<I', f.read(4))[0]
                
                self.files[path] = {
                    'offset': offset,
                    'size': size,
                    'md5': md5,
                    'flags': flags,
                    'is_new': False
                }

    def add_file(self, pck_path: str, local_path: str):
        """Queues a local file for injection/replacement."""
        if not pck_path.startswith("res://"):
            pck_path = "res://" + pck_path.lstrip("/")
            
        if not os.path.exists(local_path):
            raise FileNotFoundError(f"Local file not found: {local_path}")
            
        file_size = os.path.getsize(local_path)
        with open(local_path, 'rb') as f:
            data = f.read()
            md5_hash = hashlib.md5(data).digest()
            
        self.files[pck_path] = {
            'data': data,
            'size': file_size,
            'md5': md5_hash,
            'flags': 0,
            'is_new': True
        }
        print(f"  + Queued: {pck_path}")

    def save(self, output_filename: str):
        """Writes the new PCK file with 32-byte alignment."""
        if not self.files:
            return

        sorted_paths = sorted(self.files.keys())
        
        # Calculate Header + Index size
        # 4(magic) + 4(ver) + 4(maj) + 4(min) + 4(pat) + 64(res) + 4(count) = 88
        index_size = 88
        for path in sorted_paths:
            # 4(path_len) + path_bytes + 8(offset) + 8(size) + 16(md5) + 4(flags)
            index_size += 4 + len(path.encode('utf-8')) + 8 + 8 + 16 + 4
            
        # First file starts after the index, aligned to 32 bytes
        current_offset = (index_size + 31) & ~31
        
        for path in sorted_paths:
            self.files[path]['new_offset'] = current_offset
            # Next file aligned to 32 bytes
            current_offset = (current_offset + self.files[path]['size'] + 31) & ~31
            
        temp_file = output_filename + ".tmp"
        print(f"Writing patched PCK to {temp_file}...")
        
        try:
            with open(temp_file, 'wb') as f:
                # Write Header
                f.write(b'GDPC')
                f.write(struct.pack('<IIII', self.pck_version, self.major, self.minor, self.patch))
                f.write(b'\0' * 64)
                f.write(struct.pack('<I', len(self.files)))
                
                # Write Index
                for path in sorted_paths:
                    info = self.files[path]
                    p_bytes = path.encode('utf-8')
                    f.write(struct.pack('<I', len(p_bytes)) + p_bytes)
                    f.write(struct.pack('<QQ', info['new_offset'], info['size']))
                    f.write(info['md5'])
                    f.write(struct.pack('<I', info['flags']))
                
                # Write Data Chunks
                for path in sorted_paths:
                    info = self.files[path]
                    f.seek(info['new_offset'])
                    if info['is_new']:
                        f.write(info['data'])
                    else:
                        with open(self.source_pck, 'rb') as src:
                            src.seek(info['offset'])
                            f.write(src.read(info['size']))
                            
            # Swap files
            if os.path.exists(output_filename):
                backup_path = output_filename + ".bak"
                if not os.path.exists(backup_path):
                    print(f"Creating safety backup: {backup_path}")
                    shutil.copy2(output_filename, backup_path)
                os.remove(output_filename)
                
            os.rename(temp_file, output_filename)
            print("Successfully patched PCK.")
            
        except Exception as e:
            if os.path.exists(temp_file):
                os.remove(temp_file)
            raise e

def pack_mod_zip(mod_dir: str, output_zip: str):
    """Packs mod assets into a Godot-compatible resource ZIP."""
    print(f"Packing mod assets into {output_zip}...")
    
    exclude_dirs = ["esp_bootstrap", ".git", "__pycache__"]
    exclude_files = ["pck_patcher.py", "override.cfg", "PlayModded.sh", "PlayModded.bat"]
    
    try:
        with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(mod_dir):
                # Filter directories in-place
                dirs[:] = [d for d in dirs if d not in exclude_dirs]
                
                for file in files:
                    if file in exclude_files or file.endswith(".tmp") or file.endswith(".bak"):
                        continue
                        
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, mod_dir)
                    zf.write(full_path, rel_path)
        print("Mod assets packed successfully.")
    except Exception as e:
        print(f"Error packing mod: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="ExtraStimulantsPlus PCK & Mod Utility")
    parser.add_argument("pck", help="Path to the game's main .pck file")
    parser.add_argument("--bootstrap", help="Path to the ESPBootstrap.gd script")
    parser.add_argument("--override", help="Path to the bootstrap override.cfg")
    parser.add_argument("--pack-mod", help="Directory containing mod files to pack")
    parser.add_argument("--mod-output", help="Output path for the packed mod zip")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.pck):
        print(f"Error: PCK not found at {args.pck}")
        sys.exit(1)

    # Step 1: Bootstrap Injection
    pck = GodotPCK()
    try:
        pck.load(args.pck)
        
        # Default bootstrap paths if not provided
        script_dir = os.path.dirname(os.path.abspath(__file__))
        bootstrap_src = args.bootstrap or os.path.join(script_dir, "esp_bootstrap/ESPBootstrap.gd")
        override_src = args.override or os.path.join(script_dir, "esp_bootstrap/override.cfg")
        
        if os.path.exists(bootstrap_src) and os.path.exists(override_src):
            print("Injecting bootstrap entrypoints...")
            pck.add_file("res://esp_bootstrap/ESPBootstrap.gd", bootstrap_src)
            pck.add_file("res://override.cfg", override_src)
            pck.save(args.pck)
        else:
            print("Skipping bootstrap injection (source files not found).")
            
    except Exception as e:
        print(f"Error patching PCK: {e}")
        sys.exit(1)

    # Step 2: Mod Asset Packing
    if args.pack_mod and args.mod_output:
        pack_mod_zip(args.pack_mod, args.mod_output)

if __name__ == "__main__":
    main()
