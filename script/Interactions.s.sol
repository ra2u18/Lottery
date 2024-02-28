// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (,, address vrfCoordinator,,,,,uint256 deployerKey) = helperConfig.activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    function createSubscription(address vrfCoordinator, uint256 deployerKey) public returns (uint64) {
        console.log("Creating subscription on ChainId:", block.chainid);

        vm.startBroadcast(deployerKey);
        uint64 subscriptionId = VRFCoordinatorV2Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();

        console.log("Your subid is: ", subscriptionId);
        return subscriptionId;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (,, address vrfCoordinator,, uint64 subscriptionId,, address link, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        fundSubscription(vrfCoordinator, subscriptionId, link, deployerKey);
    }

    function fundSubscription(address vrfCoordinator, uint64 subId, address link, uint256 deployerKey) public {
        console.log("Funding subscription: ", subId);
        console.log("Using vrfCoordinator: ", vrfCoordinator);
        console.log("On chainid: ", block.chainid);

        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(subId, FUND_AMOUNT);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subId));
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        (,, address vrfCoordinator,, uint64 subscriptionId,,,uint256 deployerKey) = helperConfig.activeNetworkConfig();

        addConsumer(vrfCoordinator, subscriptionId, raffle, deployerKey);
    }

    function addConsumer(address vrfCoordinator, uint64 subscriptionId, address raffle, uint256 deployerKey) public {
        console.log("Adding consumer contract: ", raffle);
        console.log("Using vrf coordinator: ", vrfCoordinator);
        console.log("On chain id: ", block.chainid);

        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subscriptionId, raffle);
        vm.stopBroadcast();
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(raffle);
    }
}
