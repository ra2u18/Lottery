// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    // Events
    event EnteredRaffle(address indexed player);

    uint256 private entranceFee;
    uint256 private interval;
    address private vrfCoordinator;
    bytes32 private gasLane;
    uint64 private subscriptionId;
    uint32 private callbackGasLimit;
    address private link;
    uint256 private deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (entranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit, link, deployerKey) =
            helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializeInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /**
     * enter raffle
     */
    function testRaffleRevertsWhenYouDontPayEnoughEth() public {
        // Arrange
        vm.prank(PLAYER);

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);

        // ^^ the emit event should be called by the line above
        raffle.enterRaffle{value: 0.01 ether}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // pass the duration of the raffle
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__BusyCalculating.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /// CHECK-UPKEEP TESTS

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfInCalculatingState() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        assert(raffleState == Raffle.RaffleState.CALCULATING);
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

    /// PERFORM-UPKEEP TESTS
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 rState = 0;

        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep("");
    }

    // What if I need to test using the output of an event?
    modifier raffleEnteredAndModifierPassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEnteredAndModifierPassed {
        // Act
        vm.recordLogs(); // records all the emitted logs
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[0].topics[2];

        Raffle.RaffleState raffleState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    modifier skipFork() {
        if (block.chainid != 31337) return;

        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEnteredAndModifierPassed
        skipFork
    {
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndModifierPassed skipFork {
        // arrange
        uint256 additionalEntraces = 3;
        uint256 startingIndex = 1; // We have starting index = 1 because in raffleEntered modifier we already joined with somebody

        for (uint256 i = startingIndex; i < startingIndex + additionalEntraces; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimestamp = raffle.getLastTimestamp();

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[0].topics[2];

        // Pretend to be coordinator to get random nb & pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = raffle.getRecentWinner().balance;
        uint256 endTimestamp = raffle.getLastTimestamp();
        uint256 prize = entranceFee * (additionalEntraces + 1);

        assert(uint256(raffleState) == 0);
        assert(winnerBalance == STARTING_USER_BALANCE - entranceFee + prize);
        assert(endTimestamp > startingTimestamp);
    }
}
