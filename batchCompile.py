import os
import json
import re
import traceback
import solcx
from solcx import compile_source, compile_standard, install_solc
import time
import timeout_decorator
from tqdm import tqdm
import multiprocessing
from functools import partial
from optimization_set import optimization_settings
import copy
import psutil

SavePath = "/Users/xxx/testing/sol_batch_compile-main"
# limit install_solc time
# @timeout_decorator.timeout(60)
def _install_solc(version):
    install_solc(version, show_progress=True)


def check_sol_files(directory):
    """Check for Solidity files in the given directory."""
    return [filename for filename in os.listdir(directory) if filename.endswith('.sol')]

def get_version_and_filename(path):
    """Extract version and filename from metadata or inpage_meta files."""
    version, filename = None, None
    try:
        if os.path.exists(os.path.join(path, "metadata.json")):
            with open(os.path.join(path, "metadata.json"), 'r') as f:
                content = json.load(f)
                version = content["version"]
                filename = content["contract_name"]
        if filename is not None:
            version = adjust_version(version)
            return version, filename
        if os.path.exists(os.path.join(path, "inpage_meta.json")):
            with open(os.path.join(path, "inpage_meta.json"), 'r') as f:
                content = json.load(f)
                filename = content["contract_name"]
                if any(item.endswith("_" + filename + ".sol") for item in os.listdir(path)):
                    filename = [item for item in os.listdir(path) if item.endswith("_" + filename + ".sol")][0]
                if not filename.endswith(".sol"):
                    filename += ".sol"
                version = re.search(r'v(.*?)\+', content["version"]).group(1)
                # print(filename)
    

        version = adjust_version(version)
    except:
        pass
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
    if version.startswith("="):
        version = version[1:]
        return version
    if version.startswith(">="):
        version = version[2:]
        return version_map.get('^' + version[:3], version)
    if version.startswith(">"):
        version = version[1:]
        return version_map.get('^' + version[:3], version)
    return version

    



def process_directory(root):
    """Process each directory in the root directory."""
    for p in tqdm(os.listdir(root)):
        if p.endswith('.json'):
            continue
        path = os.path.join(root, p)
        os.chdir(path)
        try:
            if not check_sol_files(path):
                raise FileNotFoundError("Error: No contracts found.")
            
            version, filename = get_version_and_filename(path)
            if version not in version_list:
                _install_solc(version)
                version_list.append(version)

            for setting_id, settings in optimization_settings.items():
                try:
                    compiled_sol = compile_contract(path, version, filename, copy.deepcopy(settings))
                    with open(os.path.join(f"{SavePath}/compiled_info", p + "_" + setting_id + ".json"), "w") as file:
                        json.dump(compiled_sol, file)
                except Exception as e:
                    handle_error(e, 'compile_error/' + p + '_' + setting_id)

        except FileNotFoundError as e:
            handle_error(e, p)
        except Exception as e:
            handle_error(e, p)

def multi_process_directory(version_list, root,  p):
    @timeout_decorator.timeout(50, use_signals=True)
    def compile_contract(path, version, filename, setting):
        """Compile the contract using the given version and filename."""
        
        with open(os.path.join(path, filename), "r", encoding='utf-8') as file:
            sol_file = file.read()
            setting["sources"][filename] = {"content": sol_file}
            if int(version[2]) > 7:
                setting["settings"]["viaIR"] = True

        compiled_sol = compile_standard(setting, allow_paths=path, solc_version=version)
        return compiled_sol

    """Process each directory in the root directory."""
    path = os.path.join(root, p)
    os.chdir(path)
    try:
        
        if not check_sol_files(path):
            raise FileNotFoundError("Error: No contracts found.")
        
        version, filename = get_version_and_filename(path)

        if version not in version_list:
            _install_solc(version)
            version_list.append(version)
        
        for setting_id, settings in optimization_settings.items():
            try:
                compiled_sol = compile_contract(path, version, filename, copy.deepcopy(settings))
                with open(os.path.join(f"{SavePath}/compiled_info", p + "_" + setting_id + ".json"), "w") as file:
                    json.dump(compiled_sol, file)
            except timeout_decorator.TimeoutError as te:
                procs = psutil.Process().children()
                for pp in procs:
                    pp.terminate()
                    pp.wait()
            except Exception as e:
                handle_error(e, 'compile_error/' + p + '_' + setting_id)

    except FileNotFoundError as e:
        handle_error(e, p)
    except Exception as e:
        handle_error(e, p)

def handle_error(e, p, filename=None):
    """Handle errors and write traceback to a file."""
    # error_msg = f"{p}/{filename}:error: //" if filename else "Error"
    error_msg = f"{p}:error: //"

    # print(error_msg, e)
    with open(os.path.join(f"{SavePath}/error_info", p + ".log"), "w") as file:
        file.write(traceback.format_exc())

# Main execution
if __name__ == "__main__":
    st = time.time()
    root = f"{SavePath}/contracts"
    version_list = [_version.base_version for _version in solcx.get_installed_solc_versions()]

    num_processes = 72

    with multiprocessing.Pool(processes=num_processes) as pool:
        process_func = partial(multi_process_directory, version_list, root)
        list(tqdm(pool.imap(process_func, [p for p in os.listdir(root) if not p.endswith('.json')]), total=len(os.listdir(root))))
        pool.close()
        pool.join()
    # process_directory(root)
    ed = time.time()
    print("Total Time Cost:",ed - st)
    print("Average Time Cost:", (ed - st) / len(os.listdir(root)))
