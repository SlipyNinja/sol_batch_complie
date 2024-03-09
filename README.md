# Sol文件批量编译工具
### Requirements
* Python >= 3.6
* solcx (pip install py-solc-x)
### 执行过程
1. 运行`solcx_all_version_install.py`，预先安装所有的solidity编译器版本
2. 将合约压缩文件解压至`./contracts`
3. 修改 `handleIndividualJson.py`, `pathUpdate.py`, `batchCompile.py`中数据目录的路径`SavePath`
4. 运行`./compile.sh`完成5-6的步骤
   1. 运行`handleIndividualJson.py`以从包含合约的 json 文件中抽取并生成合约对应的 sol 文件和 `metadata.json` 文件。
   2. 运行`pathUpdate.py`以更改sol文件中所有 import 依赖路径并生成`metadata.json`文件
   3. 运行`batchCompile.py`进行批量编译


生成的编译文件放在`compile_info`目录下，若编译失败，异常信息保存在`error_info`目录下，编译异常信息保存在`error_info/compile_error`目录下。上述目录需要自行创建。

### 文件说明
`moveContracts.py` 批量移动数据
`optimization_set.py` 存储编译优化选项
`./etherscan_contract` 200个未处理的合约
`./contracts` 预处理后的合约
`./error_info` 编译报错信息
`./compiled_info` 编译结果
