import os
import json
import re
import traceback
from solcx import compile_source, compile_standard, install_solc

def check_sol_files(directory):
    """Check for Solidity files in the given directory."""
    return [filename for filename in os.listdir(directory) if filename.endswith('.sol')]

def get_version_and_filename(path):
    """Extract version and filename from metadata or inpage_meta files."""
    version, filename = None, None
    if os.path.exists(os.path.join(path, "metadata.json")):
        with open(os.path.join(path, "metadata.json"), 'r') as f:
            content = json.load(f)
            version = content["version"]
            filename = content["contract_name"]

    if os.path.exists(os.path.join(path, "inpage_meta.json")):
        with open(os.path.join(path, "inpage_meta.json"), 'r') as f:
            content = json.load(f)
            filename = content["contract_name"]
            if any(item.endswith("_" + filename + ".sol") for item in os.listdir(path)):
                filename = [item for item in os.listdir(path) if item.endswith("_" + filename + ".sol")][0]
            if not filename.endswith(".sol"):
                filename += ".sol"
            version = re.search(r'v(.*?)\+', content["version"]).group(1)
            print(filename)

    version = adjust_version(version)
    return version, filename

def adjust_version(version):
    """Adjust the version string to a specific format."""
    version_map = {
        "^0.4": "0.4.26",
        "^0.5": "0.5.17",
        "^0.6": "0.6.12",
        "^0.7": "0.7.6",
        "^0.8": "0.8.24",
    }
    for key, val in version_map.items():
        if version.startswith(key):
            return val
    if version.startswith(">="):
        version = version[2:]
        return version_map.get(version[:3], version)
    return version

def compile_contract(path, version, filename):
    """Compile the contract using the given version and filename."""
    setting = {
        "language": "Solidity",
        "sources": {},
        "settings": {
            "optimizer": {"enabled": True, "runs": 200},
            "outputSelection": {
                "*": {
                    "*": ["evm.bytecode", "evm.deployedBytecode", "devdoc", "userdoc", "metadata", "abi"]
                }
            },
            "libraries": {}
        }
    }

    with open(os.path.join(path, filename), "r", encoding='utf-8') as file:
        sol_file = file.read()
        setting["sources"][filename] = {"content": sol_file}
        if int(version[2]) > 7:
            setting["settings"]["viaIR"] = True

    compiled_sol = compile_standard(setting, solc_version=version)
    return compiled_sol

def process_directory(root):
    """Process each directory in the root directory."""
    for p in os.listdir(root):
        path = os.path.join(root, p)
        os.chdir(path)
        try:
            if not check_sol_files(path):
                raise FileNotFoundError("Error: No contracts found.")
            
            version, filename = get_version_and_filename(path)
            install_solc(version)
            compiled_sol = compile_contract(path, version, filename)

            with open(os.path.join("D:/pytest/compiled_info", p + ".json"), "w") as file:
                json.dump(compiled_sol, file)
                print(p + "/" + filename + ":COMPLETE")

        except FileNotFoundError as e:
            handle_error(e, p)
        except Exception as e:
            handle_error(e, p, filename)

def handle_error(e, p, filename=None):
    """Handle errors and write traceback to a file."""
    error_msg = f"{p}/{filename}:error: //" if filename else "Error"
    print(error_msg, e)
    with open(os.path.join("D:/sol_batch_complie/error_info", p + ".log"), "w") as file:
        file.write(traceback.format_exc())

# Main execution
if __name__ == "__main__":
    root = "D:/sol_batch_complie/contracts"
    process_directory(root)
