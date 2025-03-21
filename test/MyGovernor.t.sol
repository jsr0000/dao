// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {Box} from "../src/Box.sol";

contract MyGovernorTest is Test {
    MyGovernor public governor;
    GovToken public token;
    TimeLock public timelock;
    Box public box;

    address public user = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;
    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant VOTING_PERIOD = 50400;

    address[] public proposers;
    address[] public executors;

    uint256[] public values;
    bytes[] public calldatas;
    address[] public targets;

    function setUp() public {
        token = new GovToken(msg.sender);
        token.mint(user, INITIAL_SUPPLY);

        vm.startPrank(user);
        token.delegate(user);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(token, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        vm.prank(user);
        timelock.grantRole(proposerRole, address(governor));
        vm.prank(user);
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, user);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "store 888 in box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature(
            "store(uint256)",
            valueToStore
        );

        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        uint256 proposalId = governor.propose(
            targets,
            values,
            calldatas,
            description
        );

        console.log("Proposal State:", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        console.log("Proposal State:", uint256(governor.state(proposalId)));

        string memory reason = "lets test it";

        uint8 voteWay = 1;
        vm.prank(user);
        governor.castVoteWithReason(proposalId, voteWay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        console.log("Proposal State:", uint256(governor.state(proposalId)));

        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(box.getNumber(), valueToStore);
    }
}
