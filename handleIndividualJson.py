import json
import os
import traceback

SavePath = "/Users/xxx/testing/sol_batch_compile-main"
# Function to process the first type of JSON file
def process_type_one(file_path):
    with open(file_path, 'r', encoding='utf-8') as file:
        data = json.load(file)
    contract_name = data['ContractName']
    compiler_version = data['CompilerVersion']
    if 'sources' in data['SourceCode']:
        sources = data['SourceCode']['sources']
    else:
        sources = data['SourceCode']

    total_id = len(sources.items())
    for id, (key, value) in enumerate(sources.items()):
        file_name = str(id+1) + '_' + str(total_id) + '_' + os.path.basename(key)
        if not file_name.endswith('.sol'):
            file_name += '.sol'
        with open(file_name, 'w', encoding='utf-8') as sol_file:
            sol_file.write(value['content'])
    meta_info = {"contract_name": contract_name, "version": compiler_version}
    with open('inpage_meta.json', 'w', encoding='utf-8') as meta_file:
        json.dump(meta_info, meta_file)
    print(contract_name+"_01")

# Function to process the second type of JSON file
def process_type_two(file_path):
    with open(file_path, 'r', encoding='utf-8') as file:
        data = json.load(file)
    contract_name = data.get('ContractName')
    compiler_version = data.get('CompilerVersion')
    source_code = data.get('SourceCode')
    sol_file_name = '01_01_' + f"{contract_name}.sol"
    with open(sol_file_name, 'w', encoding='utf-8') as sol_file:
        sol_file.write(source_code)
    meta_info = {"contract_name": contract_name, "version": compiler_version}
    with open('inpage_meta.json', 'w', encoding='utf-8') as meta_file:
        json.dump(meta_info, meta_file)
    print(contract_name+"_02")
# Function to determine the type of JSON and process it
def process_json_file(file_path):
    with open(file_path, 'r', encoding='utf-8') as file:
        data = json.load(file)
    if 'SourceCode' in data and isinstance(data['SourceCode'], dict):
        process_type_one(file_path)
    else:
        process_type_two(file_path)

# Main function to iterate through directories and find JSON files
def main(directory):

    for root, dirs, files in os.walk(directory):
        try:
            if not any(item.endswith(".sol") for item in files):
                for name in files:
                    if root.split('/')[-1] not in name:
                        continue
                    if name.endswith('.json'):
                        os.chdir(root)
                        file_path = os.path.join(root, name)
                        # print(file_path)
                        with open(file_path, 'r', encoding="utf-8") as f:
                            data = json.load(f)
                            # print(len(data))
                            if isinstance(data['SourceCode'], str):
                                if data['SourceCode'].startswith("{{"):
                                    print(file_path)
                                    json_obj = json.loads(data['SourceCode'][1:-1])
                                    data['SourceCode'] = json_obj
                                else:
                                    try:
                                        json_obj = json.loads(data['SourceCode'])
                                        data['SourceCode'] = json_obj
                                    except:
                                        pass
                        with open(file_path, 'w', encoding="utf-8") as f:
                            json.dump(data,f)

                        
                        process_json_file(file_path)
                        # print(f"Processed {file_path}")
        except Exception as e:
            print(e)
            with open(f"{SavePath}/error_info/"+name+".log", "w") as file:
                file.write(traceback.format_exc())
main(f"{SavePath}/contracts")