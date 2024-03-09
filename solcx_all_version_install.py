
import solcx
from tqdm import tqdm
import multiprocessing

# 获取可安装的Solidity版本列表
version_list = solcx.get_installable_solc_versions()

# 定义安装函数
def install_solc(version):
    solcx.install_solc(version=version, show_progress=True)

if __name__ == "__main__":
    # 获取CPU核心数量，作为进程数量
    num_processes = 5
    
    # 使用进程池创建多进程
    with multiprocessing.Pool(processes=num_processes) as pool:
        # 使用map函数将安装函数应用到版本列表上
        list(tqdm(pool.imap(install_solc, [version.base_version for version in version_list]), total=len(version_list)))

    # 输出已安装的Solidity版本
    print(solcx.get_installed_solc_versions())
