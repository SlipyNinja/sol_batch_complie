
optimization_settings = {"type1": {
    "language": "Solidity",
    "sources": {},
    "settings": {
        "outputSelection": {
            "*": {
                "*": ["evm.legacyAssembly", "evm.assembly", "evm.bytecode", "evm.deployedBytecode", "devdoc", "userdoc", "metadata", "abi"]
            }
        },
        "libraries": {}
    }
},
"type2": {
    "language": "Solidity",
    "sources": {},
    "settings": {
        "optimizer": {"enabled": True, "runs": 200},
        "outputSelection": {
            "*": {
                "*": ["evm.legacyAssembly", "evm.assembly", "evm.bytecode", "evm.deployedBytecode", "devdoc", "userdoc", "metadata", "abi"]
            }
        },
        "libraries": {}
    }
},
"type3": {
    "language": "Solidity",
    "sources": {},
    "settings": {
        "optimizer": {
            "enabled": True, 
            "runs": 200, 
            "details":{
                "peephole": False
            }
            },
        "outputSelection": {
            "*": {
                "*": ["evm.legacyAssembly", "evm.assembly", "evm.bytecode", "evm.deployedBytecode", "devdoc", "userdoc", "metadata", "abi"]
            }
        },
        "libraries": {}
    }
},
"type4": {
    "language": "Solidity",
    "sources": {},
    "settings": {
        "optimizer": {
            "enabled": True, 
            "runs": 200, 
            "details":{
                "jumpdestRemover": False
            }
            },
        "outputSelection": {
            "*": {
                "*": ["evm.legacyAssembly", "evm.assembly", "evm.bytecode", "evm.deployedBytecode", "devdoc", "userdoc", "metadata", "abi"]
            }
        },
        "libraries": {}
    }
},
"type5": {
    "language": "Solidity",
    "sources": {},
    "settings": {
        "optimizer": {
            "enabled": True, 
            "runs": 200, 
            "details":{
                "yul": True,
                "yulDetails": {
                    "stackAllocation": False
                }
            }
        },
        "outputSelection": {
            "*": {
                "*": ["evm.legacyAssembly", "evm.assembly", "evm.bytecode", "evm.deployedBytecode", "devdoc", "userdoc", "metadata", "abi"]
            }
        },
        "libraries": {}
    }
},
"type6": {
    "language": "Solidity",
    "sources": {},
    "settings": {
        "optimizer": {
            "enabled": True, 
            "runs": 200, 
            "details":{
                "yul": True
            }
        },
        "outputSelection": {
            "*": {
                "*": ["evm.assembly", "evm.bytecode", "evm.deployedBytecode", "devdoc", "userdoc", "metadata", "abi"]
            }
        },
        "libraries": {}
    }
}}