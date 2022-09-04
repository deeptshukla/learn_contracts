// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.10;

error OwnersNotProvided();
error InvalidMinimumRequiredOwners(uint _minimumRequiredOwners);
error InvalidOwnerAddress(address _ownerAddress);
error NonUniqueOwnerAddress(address _repeatedOwnerAddress);
error NonOwnerNotPermitted(address _sender);
error NonExistentTransaction(uint _txId);
error TransactionAlreadyApproved(uint _txId);
error TransactionAlreadyExecuted(uint _txId);
error NeedMoreApprovals(uint _txId, uint currentApprovalCount);
error TransactionFailed(uint _txId);
error CanRevokeOnlyApprovedTransaction(uint _txId);

contract MultiSigWallet {
    event Deposit(address indexed sender, uint value);
    event Submit(uint indexed txId);
    event Approve(address indexed owner, uint indexed txId);
    event Revoke(address indexed owner, uint indexed txId);
    event Execute(uint indexed txId);

    struct Transaction {
        address to;
        uint value;
        bytes data;
        bool executed;
    }
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint public minimumRequiredOwners;
    Transaction[] public transactions;
    mapping(uint => mapping(address => bool)) public approved; // This is mapping of transactionIds to the addressToApproval status

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) {
            revert NonOwnerNotPermitted(msg.sender);
        }
        _;
    }

    modifier txExists(uint _txId) {
        if (_txId >= transactions.length) {
            revert NonExistentTransaction(_txId);
        }
        _;
    }

    modifier notApproved(uint _txId) {
        if (approved[_txId][msg.sender]) {
            revert TransactionAlreadyApproved(_txId);
        }
        _;
    }

    modifier notExecuted(uint _txId) {
        if (transactions[_txId].executed) {
            revert TransactionAlreadyExecuted(_txId);
        }
        _;
    }

    constructor(address[] memory _owners, uint _minimumRequiredOwners) payable {
        if (_owners.length == 0) {
            revert OwnersNotProvided();
        }
        if (_minimumRequiredOwners == 0) {
            revert InvalidMinimumRequiredOwners({
                _minimumRequiredOwners: _minimumRequiredOwners
            });
        }
        for (uint i; i < _owners.length; ++i) {
            address owner = _owners[i];
            if (owner == address(0)) {
                revert InvalidOwnerAddress(owner);
            }
            if (isOwner[owner]) {
                revert NonUniqueOwnerAddress(owner);
            }
            isOwner[owner] = true;
            owners.push(owner);
        }
        minimumRequiredOwners = _minimumRequiredOwners;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    function submit(
        address _to,
        uint _value,
        bytes calldata _data
    ) external onlyOwner {
        transactions.push(
            Transaction({to: _to, value: _value, data: _data, executed: false})
        );
        emit Submit(transactions.length - 1);
    }

    function approve(uint _txId)
        external
        onlyOwner
        txExists(_txId)
        notApproved(_txId)
        notExecuted(_txId)
    {
        approved[_txId][msg.sender] = true;
        emit Approve(msg.sender, _txId);
    }

    function _getApprovalCount(uint _txId) private view returns (uint count) {
        for (uint i; i < owners.length; ++i) {
            if (approved[_txId][owners[i]]) {
                ++count;
            }
        }
    }

    function execute(uint _txId)
        external
        txExists(_txId)
        notExecuted(_txId)
        onlyOwner
    {
        uint currentApprovalCount = _getApprovalCount(_txId);
        if (currentApprovalCount < minimumRequiredOwners) {
            revert NeedMoreApprovals(_txId, currentApprovalCount);
        }
        Transaction storage transaction = transactions[_txId];
        transaction.executed = true;

        // Now Doing the transaction after updating the state
        (bool success, ) = transaction.to.call{value: transaction.value}(
            transaction.data
        );
        if (!success) {
            revert TransactionFailed(_txId);
        }
        emit Execute(_txId);
    }

    function revoke(uint _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
    {
        if (!approved[_txId][msg.sender]) {
            revert CanRevokeOnlyApprovedTransaction(_txId);
        }
        approved[_txId][msg.sender] = false;

        emit Revoke(msg.sender, _txId);
    }

    function getBalance() external view returns (uint) {
        return address(this).balance;
    }
}
