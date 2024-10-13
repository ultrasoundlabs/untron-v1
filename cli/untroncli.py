#!/usr/bin/env python3

import os
import json
import sys
import argparse
from zksync2.module.module_builder import ZkSyncBuilder
from zksync2.account.wallet import Wallet 
from zksync2.manage_contracts.contract_encoder_base import (
    ContractEncoder,
    JsonConfiguration,
)
from zksync2.core.types import (
    Token,
    ZkBlockParams,
    EthBlockParams,
    ADDRESS_DEFAULT,
    StorageProof,
)
from zksync2.transaction.transaction_builders import (
    TxFunctionCall,
    TxCreateContract,
    TxCreate2Contract,
)
from zksync2.signer.eth_signer import PrivateKeyEthSigner
from web3 import Web3
from eth_account import Account
from pathlib import Path
from eth_abi import encode

# Load configuration
with open('config.json', 'r') as f:
    config = json.load(f)

def initialize_rpc_variables():
    global UNTRON_CORE_ADDRESS, ZKSYNC_URL, zk_web3
    UNTRON_CORE_ADDRESS = config['untron_core_address']
    ZKSYNC_URL = config['zksync_rpc']

    # Initialize Web3s
    zk_web3 = ZkSyncBuilder.build(ZKSYNC_URL)

def load_contract_file():
    # Load ABI
    contract_abi_path = Path("../contracts/zkout/UntronCore.sol/UntronCore.json")
    if not contract_abi_path.exists():
        print("ABI file 'UntronCore.json' not found.")
        sys.exit(1)

    with open(contract_abi_path, 'r') as abi_file:
        json_file = json.load(abi_file)
        contract_abi = json_file['abi']
        bytecode = bytes.fromhex(json_file['bytecode']["object"])
    
    return contract_abi, bytecode

def initialize_read_variables():

    initialize_rpc_variables()
    global untron_core_contract, untron_encoder
    contract_abi, bytecode = load_contract_file()

    untron_core_contract = zk_web3.eth.contract(UNTRON_CORE_ADDRESS, abi=contract_abi)
    untron_encoder = ContractEncoder(
        zk_web3, contract_abi, bytecode
    )

def initialize_write_variables():
    global PRIVATE_KEY, account, signer
    PRIVATE_KEY = config['private_key']
    account = Account.from_key(PRIVATE_KEY)
    signer = PrivateKeyEthSigner(account, zk_web3.eth.chain_id)

def deploy_untron(args):
    """
    Function to deploy the Untron contract implementation and ERC1967 proxy.
    """
    initialize_rpc_variables()
    initialize_write_variables()
    _, bytecode = load_contract_file()

    # Deploy implementation
    implementation_address = deploy_implementation(bytecode)
    print(f"UntronCore implementation deployed at {implementation_address}")

    # Deploy proxy
    proxy_address = deploy_proxy(implementation_address)
    print(f"UntronCore proxy deployed at {proxy_address}")

    config['untron_core_address'] = proxy_address
    with open('config.json', 'w') as f:
        json.dump(config, f, indent=4)
    
    initialize_read_variables() # to allow calls to the contract

    print("Deployment complete.")

def deploy_implementation(bytecode):
    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.PENDING.value
    )
    gas_price = zk_web3.zksync.gas_price
    
    create_contract = TxCreateContract(
        web3=zk_web3,
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=account.address,
        gas_limit=0,  # UNKNOWN AT THIS STATE
        gas_price=gas_price,
        bytecode=bytecode,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(create_contract.tx)

    tx_712 = create_contract.tx712(estimate_gas)

    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.zksync.send_raw_transaction(msg)
    tx_receipt = zk_web3.zksync.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    return tx_receipt["contractAddress"]

def deploy_proxy(implementation_address):
    # Load ERC1967Proxy ABI and bytecode
    proxy_abi_path = Path("../contracts/zkout/ERC1967Proxy.sol/ERC1967Proxy.json")
    if not proxy_abi_path.exists():
        print("ABI file 'ERC1967Proxy.json' not found.")
        sys.exit(1)

    with open(proxy_abi_path, 'r') as abi_file:
        json_file = json.load(abi_file)
        proxy_abi = json_file['abi']
        proxy_bytecode = bytes.fromhex(json_file['bytecode']["object"])

    # Encode the initialization data
    init_data = encode(['address', 'bytes'], [implementation_address, b"\x81\x29\xfc\x1c"]) # initialize()

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.PENDING.value
    )
    gas_price = zk_web3.zksync.gas_price

    create_contract = TxCreate2Contract(
        web3=zk_web3,
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=account.address,
        gas_limit=0,  # UNKNOWN AT THIS STATE
        gas_price=gas_price,
        bytecode=proxy_bytecode,
        salt=os.urandom(32),
        call_data=init_data,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(create_contract.tx)

    tx_712 = create_contract.tx712(estimate_gas)

    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.zksync.send_raw_transaction(msg)
    tx_receipt = zk_web3.zksync.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    return tx_receipt["contractAddress"]

# I'm not yet sure if this is needed
#
# def initialize_core():
#     nonce = zk_web3.zksync.get_transaction_count(
#         account.address, EthBlockParams.LATEST.value
#     )
#     gas_price = zk_web3.zksync.gas_price

#     call_data = untron_encoder.encode_method("initialize", [])
#     func_call = TxFunctionCall(
#         chain_id=zk_web3.eth.chain_id,
#         nonce=nonce,
#         from_=account.address,
#         to=UNTRON_CORE_ADDRESS,
#         data=call_data,
#         gas_limit=0,  # UNKNOWN AT THIS STATE,
#         gas_price=gas_price,
#     )
#     estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)

#     tx_712 = func_call.tx712(estimate_gas)

#     singed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
#     msg = tx_712.encode(singed_message)
#     tx_hash = zk_web3.zksync.send_raw_transaction(msg)
#     tx_receipt = zk_web3.zksync.wait_for_transaction_receipt(
#         tx_hash, timeout=240, poll_latency=0.5
#     )

#     print(f"Core initialized. Receipt: {tx_receipt}")

def deploy_mock_usdt(args):
    initialize_rpc_variables()
    initialize_write_variables()

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.PENDING.value
    )
    gas_price = zk_web3.zksync.gas_price
    
    contract_file = json.load(open(Path("../contracts/zkout/UntronCore.t.sol/MockUSDT.json")))
    contract_bytecode = bytes.fromhex(contract_file["bytecode"]["object"])
    create_contract = TxCreateContract(
        web3=zk_web3,
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=account.address,
        gas_limit=0,  # UNKNOWN AT THIS STATE
        gas_price=gas_price,
        bytecode=contract_bytecode,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(create_contract.tx)

    tx_712 = create_contract.tx712(estimate_gas)

    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.zksync.send_raw_transaction(msg)
    tx_receipt = zk_web3.zksync.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    contract_address = tx_receipt["contractAddress"]
    print("Deployed mock USDT at", contract_address)

def mint_mock_usdt(args):
    initialize_rpc_variables()
    initialize_write_variables()

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.PENDING.value
    )
    gas_price = zk_web3.zksync.gas_price

    contract_file = json.load(open(Path("../contracts/zkout/UntronCore.t.sol/MockUSDT.json")))
    contract_abi = contract_file["abi"]
    contract_bytecode = bytes.fromhex(contract_file["bytecode"]["object"])
    
    mock_usdt_encoder = ContractEncoder(
        zk_web3, contract_abi, contract_bytecode
    )

    call_data = mock_usdt_encoder.encode_method("mint", [account.address, 1_000_000_000])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=account.address,
        to=args.address,
        data=call_data,
        gas_limit=0,  # UNKNOWN AT THIS STATE,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)

    tx_712 = func_call.tx712(estimate_gas)

    singed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(singed_message)
    tx_hash = zk_web3.zksync.send_raw_transaction(msg)
    tx_receipt = zk_web3.zksync.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Transaction sent. Receipt: {tx_receipt}")
    print("Minted 1000 USDT to", account.address)

def create_order(args):
    initialize_write_variables()
    provider_address = Web3.to_checksum_address(args.provider)
    receiver_address = Web3.to_checksum_address(args.receiver)
    size = int(args.size)
    rate = int(args.rate)
    transfer = {
        'recipient': Web3.to_checksum_address(args.recipient),
        'chainId': int(args.chainId),
        'acrossFee': int(args.acrossFee),
        'doSwap': args.doSwap,
        'outToken': Web3.to_checksum_address(args.outToken) if args.outToken else '0x0000000000000000000000000000000000000000',
        'minOutputPerUSDT': int(args.minOutputPerUSDT),
        'fixedOutput': args.fixedOutput,
        'swapData': bytes.fromhex(args.swapData[2:]) if args.swapData.startswith('0x') else bytes.fromhex(args.swapData)
    }

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("createOrder", [provider_address, receiver_address, size, rate, transfer])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=account.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,  # UNKNOWN AT THIS STATE,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)

    tx_712 = func_call.tx712(estimate_gas)

    singed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(singed_message)
    tx_hash = zk_web3.zksync.send_raw_transaction(msg)
    tx_receipt = zk_web3.zksync.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Transaction sent. Receipt: {tx_receipt}")

def set_provider(args):
    initialize_write_variables()
    liquidity = int(args.liquidity)
    rate = int(args.rate)
    minOrderSize = int(args.minOrderSize)
    minDeposit = int(args.minDeposit)
    receivers = [Web3.to_checksum_address(receiver) for receiver in args.receivers]

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("setProvider", [liquidity, rate, minOrderSize, minDeposit, receivers])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,  # UNKNOWN AT THIS STATE,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)

    tx_712 = func_call.tx712(estimate_gas)

    singed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(singed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Transaction sent. Receipt: {tx_receipt}")

def change_order(args):
    """
    Function to change the transfer details of an existing order.
    """
    initialize_write_variables()
    order_id = args.orderId if args.orderId.startswith('0x') else '0x' + args.orderId
    transfer = {
        'recipient': Web3.to_checksum_address(args.recipient),
        'chainId': int(args.chainId),
        'acrossFee': int(args.acrossFee),
        'doSwap': args.doSwap,
        'outToken': Web3.to_checksum_address(args.outToken) if args.outToken else '0x0000000000000000000000000000000000000000',
        'minOutputPerUSDT': int(args.minOutputPerUSDT),
        'fixedOutput': args.fixedOutput,
        'swapData': bytes.fromhex(args.swapData[2:]) if args.swapData.startswith('0x') else bytes.fromhex(args.swapData)
    }

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("changeOrder", [order_id, transfer])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)
    tx_712 = func_call.tx712(estimate_gas)
    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Transaction sent. Receipt: {tx_receipt}")

def stop_order(args):
    """
    Function to stop an existing order.
    """
    initialize_write_variables()
    order_id = args.orderId if args.orderId.startswith('0x') else '0x' + args.orderId

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("stopOrder", [order_id])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)
    tx_712 = func_call.tx712(estimate_gas)
    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Order stopped. Receipt: {tx_receipt}")

def fulfill(args):
    """
    Function to fulfill orders by sending their ask in advance.
    """
    initialize_write_variables()
    order_ids = [order_id if order_id.startswith('0x') else '0x' + order_id for order_id in args.orderIds]
    total = int(args.total)

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("fulfill", [order_ids, total])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)
    tx_712 = func_call.tx712(estimate_gas)
    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Orders fulfilled. Receipt: {tx_receipt}")

def close_orders(args):
    """
    Function to close orders and send funds to providers or order creators.
    """
    initialize_write_variables()
    # Assuming proof and publicValues are hex strings starting with '0x'
    proof = bytes.fromhex(args.proof[2:] if args.proof.startswith('0x') else args.proof)
    public_values = bytes.fromhex(args.publicValues[2:] if args.publicValues.startswith('0x') else args.publicValues)

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("closeOrders", [proof, public_values])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)
    tx_712 = func_call.tx712(estimate_gas)
    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Orders closed. Receipt: {tx_receipt}")

def set_zk_variables(args):
    """
    Function to update the UntronZK-related variables.
    """
    initialize_write_variables()
    trusted_relayer = Web3.to_checksum_address(args.trustedRelayer)
    verifier = Web3.to_checksum_address(args.verifier)
    vkey = args.vkey if args.vkey.startswith('0x') else '0x' + args.vkey

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("setZKVariables", [trusted_relayer, verifier, vkey])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)
    tx_712 = func_call.tx712(estimate_gas)
    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"ZK variables set. Receipt: {tx_receipt}")

def set_transfers_variables(args):
    """
    Function to update the UntronTransfers-related variables.
    """
    initialize_write_variables()
    usdt = Web3.to_checksum_address(args.usdt)
    spoke_pool = Web3.to_checksum_address(args.spokePool)
    swapper = Web3.to_checksum_address(args.swapper)

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("setTransfersVariables", [usdt, spoke_pool, swapper])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)
    tx_712 = func_call.tx712(estimate_gas)
    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Transfers variables set. Receipt: {tx_receipt}")

def set_fees_variables(args):
    """
    Function to update the UntronFees-related variables.
    """
    initialize_write_variables()
    relayer_fee = int(args.relayerFee)
    fee_point = int(args.feePoint)

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("setFeesVariables", [relayer_fee, fee_point])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)
    tx_712 = func_call.tx712(estimate_gas)
    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Fees variables set. Receipt: {tx_receipt}")

def set_core_variables(args):
    """
    Function to update the UntronCore-related variables.
    """
    initialize_write_variables()
    block_id = args.blockId if args.blockId.startswith('0x') else '0x' + args.blockId
    action_chain_tip = args.actionChainTip if args.actionChainTip.startswith('0x') else '0x' + args.actionChainTip
    latest_executed_action = args.latestExecutedAction if args.latestExecutedAction.startswith('0x') else '0x' + args.latestExecutedAction
    state_hash = args.stateHash if args.stateHash.startswith('0x') else '0x' + args.stateHash
    max_order_size = int(args.maxOrderSize)
    required_collateral = int(args.requiredCollateral)

    nonce = zk_web3.zksync.get_transaction_count(
        account.address, EthBlockParams.LATEST.value
    )
    gas_price = zk_web3.zksync.gas_price

    call_data = untron_encoder.encode_method("setCoreVariables", [
        block_id,
        action_chain_tip,
        latest_executed_action,
        state_hash,
        max_order_size,
        required_collateral
    ])
    func_call = TxFunctionCall(
        chain_id=zk_web3.eth.chain_id,
        nonce=nonce,
        from_=signer.address,
        to=UNTRON_CORE_ADDRESS,
        data=call_data,
        gas_limit=0,
        gas_price=gas_price,
        max_priority_fee_per_gas=0,
    )
    estimate_gas = zk_web3.zksync.eth_estimate_gas(func_call.tx)
    tx_712 = func_call.tx712(estimate_gas)
    signed_message = signer.sign_typed_data(tx_712.to_eip712_struct())
    msg = tx_712.encode(signed_message)
    tx_hash = zk_web3.eth.send_raw_transaction(msg)
    tx_receipt = zk_web3.eth.wait_for_transaction_receipt(
        tx_hash, timeout=240, poll_latency=0.5
    )

    print(f"Core variables set. Receipt: {tx_receipt}")

def providers(args):
    """
    Function to get the provider details.
    """
    initialize_read_variables()
    provider = Web3.to_checksum_address(args.provider)
    result = untron_core_contract.functions.providers(provider).call()
    print(f"Provider details: {result}")

def is_receiver_busy(args):
    """
    Function to check if a receiver is busy.
    """
    initialize_read_variables()
    receiver = Web3.to_checksum_address(args.receiver)
    result = untron_core_contract.functions.isReceiverBusy(receiver).call()
    print(f"Is receiver busy: {result}")

def receiver_owners(args):
    """
    Function to get the owner of a receiver.
    """
    initialize_read_variables()
    receiver = Web3.to_checksum_address(args.receiver)
    result = untron_core_contract.functions.receiverOwners(receiver).call()
    print(f"Receiver owner: {result}")

def orders(args):
    """
    Function to get order details.
    """
    initialize_read_variables()
    order_id = args.orderId if args.orderId.startswith('0x') else '0x' + args.orderId
    result = untron_core_contract.functions.orders(order_id).call()
    print(f"Order details: {result}")

def block_id(args):
    """
    Function to get the current block ID.
    """
    initialize_read_variables()
    result = untron_core_contract.functions.blockId().call()
    print(f"Current block ID: {result}")

def action_chain_tip(args):
    """
    Function to get the current action chain tip.
    """
    initialize_read_variables()
    result = untron_core_contract.functions.actionChainTip().call()
    print(f"Current action chain tip: {result}")

def latest_executed_action(args):
    """
    Function to get the latest executed action.
    """
    initialize_read_variables()
    result = untron_core_contract.functions.latestExecutedAction().call()
    print(f"Latest executed action: {result}")

def state_hash(args):
    """
    Function to get the current state hash.
    """
    initialize_read_variables()
    result = untron_core_contract.functions.stateHash().call()
    print(f"Current state hash: {result}")

def max_order_size(args):
    """
    Function to get the maximum order size.
    """
    initialize_read_variables()
    result = untron_core_contract.functions.maxOrderSize().call()
    print(f"Maximum order size: {result}")

def required_collateral(args):
    """
    Function to get the required collateral.
    """
    initialize_read_variables()
    result = untron_core_contract.functions.requiredCollateral().call()
    print(f"Required collateral: {result}")

def calculate_fulfiller_total(args):
    """
    Function to calculate the fulfiller's total expense and income.
    """
    initialize_read_variables()
    order_ids = [order_id if order_id.startswith('0x') else '0x' + order_id for order_id in args.orderIds]
    result = untron_core_contract.functions.calculateFulfillerTotal(order_ids).call()
    print(f"Fulfiller total - Expense: {result[0]}, Profit: {result[1]}")


def main():
    parser = argparse.ArgumentParser(description='UntronCore CLI')
    subparsers = parser.add_subparsers(title='Commands')

    # DEPLOYMENT FUNCTIONS

    parser_deploy_untron = subparsers.add_parser('deploy', help='Deploy UntronCore contract into a proxy')
    parser_deploy_untron.set_defaults(func=deploy_untron)

    parser_deploy_mock_usdt = subparsers.add_parser('deployMockUSDT', help='Deploy MockUSDT contract and mint 1000 USDT to the account')
    parser_deploy_mock_usdt.set_defaults(func=deploy_mock_usdt)

    # WRITE FUNCTIONS

    parser_mint_mock_usdt = subparsers.add_parser('mintMockUSDT', help='Mint 1000 MockUSDT to the account')
    parser_mint_mock_usdt.add_argument('--address', required=True, help='MockUSDT contract address')
    parser_mint_mock_usdt.set_defaults(func=mint_mock_usdt)

    # createOrder command
    parser_create_order = subparsers.add_parser('createOrder', help='Create a new order (WRITE FUNCTION)')
    parser_create_order.add_argument('--provider', required=True, help='Provider address')
    parser_create_order.add_argument('--receiver', required=True, help='Receiver address')
    parser_create_order.add_argument('--size', required=True, help='Order size')
    parser_create_order.add_argument('--rate', required=True, help='Order rate')
    parser_create_order.add_argument('--recipient', required=True, help='Transfer recipient')
    parser_create_order.add_argument('--chainId', required=True, help='Transfer chain ID')
    parser_create_order.add_argument('--acrossFee', default='0', help='Across bridge fee')
    parser_create_order.add_argument('--doSwap', action='store_true', help='Perform swap')
    parser_create_order.add_argument('--outToken', help='Output token address')
    parser_create_order.add_argument('--minOutputPerUSDT', default='0', help='Min output per USDT')
    parser_create_order.add_argument('--fixedOutput', action='store_true', help='Fixed output amount')
    parser_create_order.add_argument('--swapData', default='', help='Swap data in hex')
    parser_create_order.set_defaults(func=create_order)

    # setProvider command
    parser_set_provider = subparsers.add_parser('setProvider', help='Set provider details (WRITE FUNCTION)')
    parser_set_provider.add_argument('--liquidity', required=True, help='Liquidity amount')
    parser_set_provider.add_argument('--rate', required=True, help='Rate')
    parser_set_provider.add_argument('--minOrderSize', required=True, help='Minimum order size')
    parser_set_provider.add_argument('--minDeposit', required=True, help='Minimum deposit')
    parser_set_provider.add_argument('--receivers', nargs='+', required=True, help='Receiver addresses')
    parser_set_provider.set_defaults(func=set_provider)

    # changeOrder command
    parser_change_order = subparsers.add_parser('changeOrder', help='Change transfer details of an order (WRITE FUNCTION)')
    parser_change_order.add_argument('--orderId', required=True, help='Order ID')
    parser_change_order.add_argument('--recipient', required=True, help='Transfer recipient')
    parser_change_order.add_argument('--chainId', required=True, help='Transfer chain ID')
    parser_change_order.add_argument('--acrossFee', default='0', help='Across bridge fee')
    parser_change_order.add_argument('--doSwap', action='store_true', help='Perform swap')
    parser_change_order.add_argument('--outToken', help='Output token address')
    parser_change_order.add_argument('--minOutputPerUSDT', default='0', help='Min output per USDT')
    parser_change_order.add_argument('--fixedOutput', action='store_true', help='Fixed output amount')
    parser_change_order.add_argument('--swapData', default='', help='Swap data in hex')
    parser_change_order.set_defaults(func=change_order)

    # stopOrder command
    parser_stop_order = subparsers.add_parser('stopOrder', help='Stop an existing order (WRITE FUNCTION)')
    parser_stop_order.add_argument('--orderId', required=True, help='Order ID')
    parser_stop_order.set_defaults(func=stop_order)

    # fulfill command
    parser_fulfill = subparsers.add_parser('fulfill', help='Fulfill orders by sending their ask in advance (WRITE FUNCTION)')
    parser_fulfill.add_argument('--orderIds', nargs='+', required=True, help='List of order IDs')
    parser_fulfill.add_argument('--total', required=True, help='Total amount of USDT L2 to transfer')
    parser_fulfill.set_defaults(func=fulfill)

    # closeOrders command
    parser_close_orders = subparsers.add_parser('closeOrders', help='Close orders and send funds (WRITE FUNCTION)')
    parser_close_orders.add_argument('--proof', required=True, help='ZK proof in hex')
    parser_close_orders.add_argument('--publicValues', required=True, help='Public values in hex')
    parser_close_orders.set_defaults(func=close_orders)

    # setZKVariables command
    parser_set_zk_variables = subparsers.add_parser('setZKVariables', help='Set ZK variables (WRITE FUNCTION)')
    parser_set_zk_variables.add_argument('--trustedRelayer', required=True, help='Trusted relayer address')
    parser_set_zk_variables.add_argument('--verifier', required=True, help='Verifier contract address')
    parser_set_zk_variables.add_argument('--vkey', required=True, help='Verification key (bytes32)')
    parser_set_zk_variables.set_defaults(func=set_zk_variables)

    # setTransfersVariables command
    parser_set_transfers_variables = subparsers.add_parser('setTransfersVariables', help='Set transfers variables (WRITE FUNCTION)')
    parser_set_transfers_variables.add_argument('--usdt', required=True, help='USDT token address')
    parser_set_transfers_variables.add_argument('--spokePool', required=True, help='SpokePool contract address')
    parser_set_transfers_variables.add_argument('--swapper', required=True, help='Swapper contract address')
    parser_set_transfers_variables.set_defaults(func=set_transfers_variables)

    # setFeesVariables command
    parser_set_fees_variables = subparsers.add_parser('setFeesVariables', help='Set fees variables (WRITE FUNCTION)')
    parser_set_fees_variables.add_argument('--relayerFee', required=True, help='Relayer fee (in percents)')
    parser_set_fees_variables.add_argument('--feePoint', required=True, help='Fee point')
    parser_set_fees_variables.set_defaults(func=set_fees_variables)

    # setCoreVariables command
    parser_set_core_variables = subparsers.add_parser('setCoreVariables', help='Set core variables (WRITE FUNCTION)')
    parser_set_core_variables.add_argument('--blockId', required=True, help='Block ID (bytes32)')
    parser_set_core_variables.add_argument('--actionChainTip', required=True, help='Action chain tip (bytes32)')
    parser_set_core_variables.add_argument('--latestExecutedAction', required=True, help='Latest executed action (bytes32)')
    parser_set_core_variables.add_argument('--stateHash', required=True, help='State hash (bytes32)')
    parser_set_core_variables.add_argument('--maxOrderSize', required=True, help='Max order size (uint256)')
    parser_set_core_variables.add_argument('--requiredCollateral', required=True, help='Required collateral (uint256)')
    parser_set_core_variables.set_defaults(func=set_core_variables)

    # READ FUNCTIONS

    parser_providers = subparsers.add_parser('providers', help='Get provider details')
    parser_providers.add_argument('--provider', required=True, help='Provider address')
    parser_providers.set_defaults(func=providers)

    parser_is_receiver_busy = subparsers.add_parser('isReceiverBusy', help='Check if a receiver is busy')
    parser_is_receiver_busy.add_argument('--receiver', required=True, help='Receiver address')
    parser_is_receiver_busy.set_defaults(func=is_receiver_busy)

    parser_receiver_owners = subparsers.add_parser('receiverOwners', help='Get the owner of a receiver')
    parser_receiver_owners.add_argument('--receiver', required=True, help='Receiver address')
    parser_receiver_owners.set_defaults(func=receiver_owners)

    parser_orders = subparsers.add_parser('orders', help='Get order details')
    parser_orders.add_argument('--orderId', required=True, help='Order ID')
    parser_orders.set_defaults(func=orders)

    parser_block_id = subparsers.add_parser('blockId', help='Get the current block ID')
    parser_block_id.set_defaults(func=block_id)

    parser_action_chain_tip = subparsers.add_parser('actionChainTip', help='Get the current action chain tip')
    parser_action_chain_tip.set_defaults(func=action_chain_tip)

    parser_latest_executed_action = subparsers.add_parser('latestExecutedAction', help='Get the latest executed action')
    parser_latest_executed_action.set_defaults(func=latest_executed_action)

    parser_state_hash = subparsers.add_parser('stateHash', help='Get the current state hash')
    parser_state_hash.set_defaults(func=state_hash)

    parser_max_order_size = subparsers.add_parser('maxOrderSize', help='Get the maximum order size')
    parser_max_order_size.set_defaults(func=max_order_size)

    parser_required_collateral = subparsers.add_parser('requiredCollateral', help='Get the required collateral')
    parser_required_collateral.set_defaults(func=required_collateral)

    parser_calculate_fulfiller_total = subparsers.add_parser('calculateFulfillerTotal', help='Calculate the fulfiller\'s total expense and income')
    parser_calculate_fulfiller_total.add_argument('--orderIds', nargs='+', required=True, help='List of order IDs')
    parser_calculate_fulfiller_total.set_defaults(func=calculate_fulfiller_total)

    args = parser.parse_args()
    if hasattr(args, 'func'):
        args.func(args)
    else:
        parser.print_help()

if __name__ == '__main__':
    main()