// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {LedgerLounge} from "../src/LedgerLounge.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockCUSD is ERC20 {
    constructor() ERC20("Celo Dollar", "cUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LedgerLoungeTest is Test {
    LedgerLounge ledgerLounge;
    MockCUSD cusd;

    address host = makeAddr("host");
    address guest = makeAddr("guest");
    address other = makeAddr("other");

    function setUp() public {
        cusd = new MockCUSD();
        ledgerLounge = new LedgerLounge(address(cusd));
    }

    // Test property creation
    function testCreateProperty() public {
        vm.prank(host);
        ledgerLounge.createProperty("Beach House", "Miami", "ipfs://...", 1 ether, 0);

        LedgerLounge.Property memory prop = ledgerLounge.getProperty(1);
        assertEq(prop.host, host);
        assertEq(prop.title, "Beach House");
        assertEq(prop.location, "Miami");
        assertEq(prop.metadataURI, "ipfs://...");
        assertEq(prop.nightlyPrice, 1 ether);
        assertEq(uint256(prop.paymentAsset), 0);
        assertTrue(prop.active);
    }

    function testCreatePropertyWithCusd() public {
        vm.prank(host);
        ledgerLounge.createProperty("Mountain Cabin", "Colorado", "ipfs://...", 2 ether, 1);

        LedgerLounge.Property memory prop = ledgerLounge.getProperty(1);
        assertEq(uint256(prop.paymentAsset), 1);
    }

    function testRevertCreatePropertyInvalidPrice() public {
        vm.prank(host);
        vm.expectRevert(LedgerLounge.LedgerLounge__InvalidPrice.selector);
        ledgerLounge.createProperty("House", "Location", "URI", 0, 0);
    }

    function testRevertCreatePropertyInvalidPaymentAsset() public {
        vm.prank(host);
        vm.expectRevert(LedgerLounge.LedgerLounge__InvalidPaymentAsset.selector);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 2);
    }

    // Test setPropertyActive
    function testSetPropertyActive() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        vm.prank(host);
        ledgerLounge.setPropertyActive(1, false);

        LedgerLounge.Property memory prop = ledgerLounge.getProperty(1);
        assertFalse(prop.active);
    }

    function testRevertSetPropertyActiveNotHost() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        vm.prank(other);
        vm.expectRevert(LedgerLounge.LedgerLounge__NotHost.selector);
        ledgerLounge.setPropertyActive(1, false);
    }

    // Test booking with CELO
    function testBookWithCelo() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        uint256 checkIn = block.timestamp + 1 days;
        uint256 checkOut = checkIn + 2 days; // 2 nights

        uint256 initialHostBalance = host.balance;

        vm.deal(guest, 3 ether);
        vm.prank(guest);
        ledgerLounge.book{value: 2 ether}(1, checkIn, checkOut);

        assertEq(host.balance, initialHostBalance + 2 ether);

        LedgerLounge.Booking memory booking = ledgerLounge.getBooking(1);
        assertEq(booking.propertyId, 1);
        assertEq(booking.guest, guest);
        assertEq(booking.checkInDate, checkIn);
        assertEq(booking.checkOutDate, checkOut);
        assertEq(booking.totalPrice, 2 ether);
        assertEq(uint256(booking.paymentAsset), 0);
        assertTrue(booking.active);
    }

    // Test booking with cUSD
    function testBookWithCusd() public {
        cusd.mint(guest, 3 ether);

        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 1);

        uint256 checkIn = block.timestamp + 1 days;
        uint256 checkOut = checkIn + 2 days;

        vm.prank(guest);
        cusd.approve(address(ledgerLounge), 2 ether);

        vm.prank(guest);
        ledgerLounge.book(1, checkIn, checkOut);

        assertEq(cusd.balanceOf(host), 2 ether);
        assertEq(cusd.balanceOf(guest), 1 ether);
    }

    // Test revert cases for booking
    function testRevertBookPropertyDoesNotExist() public {
        vm.prank(guest);
        vm.expectRevert(LedgerLounge.LedgerLounge__PropertyDoesNotExist.selector);
        ledgerLounge.book(999, block.timestamp + 1 days, block.timestamp + 2 days);
    }

    function testRevertBookPropertyNotActive() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        vm.prank(host);
        ledgerLounge.setPropertyActive(1, false);

        vm.prank(guest);
        vm.expectRevert(LedgerLounge.LedgerLounge__PropertyNotActive.selector);
        ledgerLounge.book(1, block.timestamp + 1 days, block.timestamp + 2 days);
    }

    function testRevertBookInvalidDates() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        vm.prank(guest);
        vm.expectRevert(LedgerLounge.LedgerLounge__InvalidDates.selector);
        ledgerLounge.book(1, block.timestamp + 2 days, block.timestamp + 1 days);
    }

    function testRevertBookZeroNights() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        vm.prank(guest);
        vm.expectRevert(LedgerLounge.LedgerLounge__InvalidDates.selector);
        ledgerLounge.book(1, block.timestamp + 1 days, block.timestamp + 1 days);
    }

    function testRevertBookIncorrectPaymentAmountCelo() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        vm.deal(guest, 3 ether);
        vm.prank(guest);
        vm.expectRevert(LedgerLounge.LedgerLounge__IncorrectPaymentAmount.selector);
        ledgerLounge.book{value: 0}(1, block.timestamp + 1 days, block.timestamp + 2 days);
    }

    function testRevertBookIncorrectPaymentAmountCusd() public {
        cusd.mint(guest, 3 ether);

        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 1);

        vm.prank(guest);
        cusd.approve(address(ledgerLounge), 2 ether);

        vm.deal(guest, 1 ether); // Give guest CELO to send, even though it's incorrect
        vm.prank(guest);
        vm.expectRevert(LedgerLounge.LedgerLounge__IncorrectPaymentAmount.selector);
        ledgerLounge.book{value: 1 ether}(1, block.timestamp + 1 days, block.timestamp + 2 days);
    }

    // Test overlap
    function testRevertBookOverlap() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        uint256 checkIn1 = block.timestamp + 1 days;
        uint256 checkOut1 = checkIn1 + 2 days;

        vm.deal(guest, 5 ether);
        vm.prank(guest);
        ledgerLounge.book{value: 2 ether}(1, checkIn1, checkOut1);

        // Try overlapping booking
        uint256 checkIn2 = checkIn1 + 1 days;
        uint256 checkOut2 = checkOut1 + 1 days;

        vm.deal(other, 3 ether); // Give other CELO to send
        vm.prank(other);
        vm.expectRevert(LedgerLounge.LedgerLounge__DatesNotAvailable.selector);
        ledgerLounge.book{value: 2 ether}(1, checkIn2, checkOut2);
    }

    // Test isDateRangeAvailable
    function testIsDateRangeAvailable() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        uint256 checkIn = block.timestamp + 1 days;
        uint256 checkOut = checkIn + 2 days;

        bool available = ledgerLounge.isDateRangeAvailable(1, checkIn, checkOut);
        assertTrue(available);

        vm.deal(guest, 3 ether);
        vm.prank(guest);
        ledgerLounge.book{value: 2 ether}(1, checkIn, checkOut);

        available = ledgerLounge.isDateRangeAvailable(1, checkIn, checkOut);
        assertFalse(available);
    }

    // Test view functions
    function testGetPropertyBookings() public {
        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        vm.deal(guest, 3 ether);
        vm.prank(guest);
        ledgerLounge.book{value: 2 ether}(1, block.timestamp + 1 days, block.timestamp + 3 days);

        uint256[] memory bookings = ledgerLounge.getPropertyBookings(1);
        assertEq(bookings.length, 1);
        assertEq(bookings[0], 1);
    }

    function testGetNextIds() public {
        assertEq(ledgerLounge.getNextPropertyId(), 1);
        assertEq(ledgerLounge.getNextBookingId(), 1);

        vm.prank(host);
        ledgerLounge.createProperty("House", "Location", "URI", 1 ether, 0);

        assertEq(ledgerLounge.getNextPropertyId(), 2);
        assertEq(ledgerLounge.getNextBookingId(), 1);
    }
}