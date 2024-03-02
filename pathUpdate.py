import os
import re
import json

def compare_versions(version):
    """比较版本号，用于排序"""
    version_parts = [int(part) for part in re.findall(r'\d+', version)]
    return version_parts[1], version_parts[-1]

def find_solidity_files(base_path):
    """遍历目录查找Solidity文件，并生成metadata.json"""
    print(f"Searching for Solidity files in {base_path}...")
    found_files = False
    for root, _, files in os.walk(base_path):
        for file in files: 
            if file.endswith('.sol'):
                full_path = os.path.join(root, file).replace("\\", "/")
                if file.startswith("01") or not file[0].isdigit():
                    process_file(full_path)
                    found_files = True
    if not found_files:
        print("No Solidity files found.")

def process_file(full_path):
    """处理单个Solidity文件，提取版本信息并保存到metadata.json"""
    try:
        with open(full_path, 'r', encoding='utf-8') as file:
            content = file.read()
        pattern = r'pragma\s+solidity\s+(\^?>?=?\d+\.\d+\.\d+)'
        matches = re.findall(pattern, content)
        if matches:
            root_path = os.path.dirname(full_path)
            metadata_path = os.path.join(root_path, "metadata.json")
            with open(metadata_path, "w") as file:
                json.dump({"contract_name": os.path.basename(full_path), "version": max(matches, key=compare_versions)}, file)
            print(f"Metadata for {os.path.basename(full_path)} saved to {metadata_path}.")
    except Exception as e:
        print(f"Error processing file {full_path}: {e}")

def update_file_references(base_path):
    """更新文件中的引用路径"""
    print("Updating file references...")
    for root, dirs, files in os.walk(base_path):
        for file in files:
            if file.endswith('.sol'):
                update_references(os.path.join(root, file))

def update_references(file_path):
    """更新一个文件中的所有引用路径"""
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            content = file.read()
        updated_content = update_content(content, os.listdir(os.path.dirname(file_path)))
        with open(file_path, 'w', encoding='utf-8') as file:
            file.write(updated_content)
        print(f"References in {file_path} have been updated.")
    except Exception as e:
        print(f"Error updating references in {file_path}: {e}")

def update_content(content, file_list):
    """在文件内容中更新引用路径"""
    for filename in file_list:
        if filename.endswith('.sol'):
            pattern = rf'([\'"])((?:(?!\1).)*{re.escape("/"+"_".join(filename.split("_")[2:]))}\1)'
            replacement = f'"{r"./"+filename}"'
            content = re.sub(pattern, replacement, content)
    return content

def main():
    base_path = 'D:/sol_batch_complie/contracts'
    try:
        find_solidity_files(base_path)
        update_file_references(base_path)
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == '__main__':
    main()
