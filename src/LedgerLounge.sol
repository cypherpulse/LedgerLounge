// SPDX-License-Identifier: MIT
// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract

// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LedgerLounge
 * @notice A real-estate booking smart contract on Celo for property listings and bookings with CELO or cUSD payments.
 * @dev Hosts can list properties, guests can book date ranges. Prevents overlapping bookings. Payments are forwarded directly to hosts.
 */
contract LedgerLounge {
    // Custom errors
    error LedgerLounge__InvalidPrice();
    error LedgerLounge__InvalidDates();
    error LedgerLounge__PropertyDoesNotExist();
    error LedgerLounge__PropertyNotActive();
    error LedgerLounge__NotHost();
    error LedgerLounge__DatesNotAvailable();
    error LedgerLounge__IncorrectPaymentAmount();
    error LedgerLounge__InvalidPaymentAsset();
    error LedgerLounge__PaymentFailed();

    // Type declarations
    enum PaymentAsset {
        CELO,
        CUSD
    }

    struct Property {
        address host;
        string title;
        string location;
        string metadataURI;
        uint256 nightlyPrice;
        PaymentAsset paymentAsset;
        bool active;
    }

    struct Booking {
        uint256 propertyId;
        address guest;
        uint256 checkInDate;
        uint256 checkOutDate;
        uint256 totalPrice;
        PaymentAsset paymentAsset;
        bool active;
    }

    // State variables
    IERC20 public immutable I_CUSD;
    uint256 private sNextPropertyId = 1;
    uint256 private sNextBookingId = 1;
    mapping(uint256 => Property) private sProperties;
    mapping(uint256 => Booking) private sBookings;
    mapping(uint256 => uint256[]) private sPropertyBookings;

    // Events
    event PropertyCreated(
        uint256 indexed propertyId,
        address indexed host,
        string title,
        uint256 nightlyPrice,
        PaymentAsset paymentAsset
    );

    event PropertyStatusUpdated(uint256 indexed propertyId, bool active);

    event BookingCreated(
        uint256 indexed bookingId,
        uint256 indexed propertyId,
        address indexed guest,
        uint256 checkInDate,
        uint256 checkOutDate,
        uint256 totalPrice,
        PaymentAsset paymentAsset
    );

    // Modifiers
    // No modifiers needed for this contract

    // Functions

    /**
     * @notice Constructor to initialize the contract with cUSD token address.
     * @param cusd The address of the cUSD ERC-20 token on Celo.
     */
    constructor(address cusd) {
        I_CUSD = IERC20(cusd);
    }

    /**
     * @notice Creates a new property listing.
     * @param title The title of the property.
     * @param location The location of the property.
     * @param metadataURI URI for off-chain metadata (e.g., IPFS).
     * @param nightlyPrice The price per night in the specified asset (18 decimals).
     * @param paymentAsset The asset for payments (0 for CELO, 1 for CUSD).
     */
    function createProperty(
        string memory title,
        string memory location,
        string memory metadataURI,
        uint256 nightlyPrice,
        uint256 paymentAsset
    ) external {
        if (nightlyPrice == 0) revert LedgerLounge__InvalidPrice();
        if (paymentAsset > 1) revert LedgerLounge__InvalidPaymentAsset();

        PaymentAsset asset = PaymentAsset(paymentAsset);

        uint256 propertyId = sNextPropertyId++;
        sProperties[propertyId] = Property({
            host: msg.sender,
            title: title,
            location: location,
            metadataURI: metadataURI,
            nightlyPrice: nightlyPrice,
            paymentAsset: asset,
            active: true
        });

        emit PropertyCreated(propertyId, msg.sender, title, nightlyPrice, asset);
    }

    /**
     * @notice Sets the active status of a property (host only).
     * @param propertyId The ID of the property.
     * @param active The new active status.
     */
    function setPropertyActive(uint256 propertyId, bool active) external {
        if (sProperties[propertyId].host != msg.sender) revert LedgerLounge__NotHost();
        sProperties[propertyId].active = active;
        emit PropertyStatusUpdated(propertyId, active);
    }

    /**
     * @notice Books a property for a date range and handles payment.
     * @param propertyId The ID of the property to book.
     * @param checkInDate The check-in date (UNIX timestamp, inclusive).
     * @param checkOutDate The check-out date (UNIX timestamp, exclusive).
     */
    function book(uint256 propertyId, uint256 checkInDate, uint256 checkOutDate) external payable {
        Property memory property = sProperties[propertyId];
        if (property.host == address(0)) revert LedgerLounge__PropertyDoesNotExist();
        if (!property.active) revert LedgerLounge__PropertyNotActive();
        if (checkInDate >= checkOutDate) revert LedgerLounge__InvalidDates();

        uint256 nights = (checkOutDate - checkInDate) / 1 days;
        if (nights == 0) revert LedgerLounge__InvalidDates();

        uint256 totalPrice = nights * property.nightlyPrice;

        // Check for overlapping bookings
        uint256[] memory bookingIds = sPropertyBookings[propertyId];
        for (uint256 i = 0; i < bookingIds.length; i++) {
            Booking memory existing = sBookings[bookingIds[i]];
            if (
                existing.active &&
                checkInDate < existing.checkOutDate &&
                checkOutDate > existing.checkInDate
            ) {
                revert LedgerLounge__DatesNotAvailable();
            }
        }

        // Handle payment
        if (property.paymentAsset == PaymentAsset.CELO) {
            if (msg.value != totalPrice) revert LedgerLounge__IncorrectPaymentAmount();
            (bool success, ) = payable(property.host).call{value: totalPrice}("");
            if (!success) revert LedgerLounge__PaymentFailed();
        } else {
            if (msg.value != 0) revert LedgerLounge__IncorrectPaymentAmount();
            bool success = I_CUSD.transferFrom(msg.sender, property.host, totalPrice);
            if (!success) revert LedgerLounge__PaymentFailed();
        }

        // Create booking
        uint256 bookingId = sNextBookingId++;
        sBookings[bookingId] = Booking({
            propertyId: propertyId,
            guest: msg.sender,
            checkInDate: checkInDate,
            checkOutDate: checkOutDate,
            totalPrice: totalPrice,
            paymentAsset: property.paymentAsset,
            active: true
        });
        sPropertyBookings[propertyId].push(bookingId);

        emit BookingCreated(
            bookingId,
            propertyId,
            msg.sender,
            checkInDate,
            checkOutDate,
            totalPrice,
            property.paymentAsset
        );
    }

    // View & pure functions

    /**
     * @notice Gets the details of a property.
     * @param propertyId The ID of the property.
     * @return The Property struct.
     */
    function getProperty(uint256 propertyId) external view returns (Property memory) {
        return sProperties[propertyId];
    }

    /**
     * @notice Gets the details of a booking.
     * @param bookingId The ID of the booking.
     * @return The Booking struct.
     */
    function getBooking(uint256 bookingId) external view returns (Booking memory) {
        return sBookings[bookingId];
    }

    /**
     * @notice Gets the list of booking IDs for a property.
     * @param propertyId The ID of the property.
     * @return Array of booking IDs.
     */
    function getPropertyBookings(uint256 propertyId) external view returns (uint256[] memory) {
        return sPropertyBookings[propertyId];
    }

    /**
     * @notice Gets the next property ID to be assigned.
     * @return The next property ID.
     */
    function getNextPropertyId() external view returns (uint256) {
        return sNextPropertyId;
    }

    /**
     * @notice Gets the next booking ID to be assigned.
     * @return The next booking ID.
     */
    function getNextBookingId() external view returns (uint256) {
        return sNextBookingId;
    }

    /**
     * @notice Checks if a date range is available for booking on a property.
     * @param propertyId The ID of the property.
     * @param checkInDate The check-in date.
     * @param checkOutDate The check-out date.
     * @return True if available, false otherwise.
     */
    function isDateRangeAvailable(
        uint256 propertyId,
        uint256 checkInDate,
        uint256 checkOutDate
    ) external view returns (bool) {
        uint256[] memory bookingIds = sPropertyBookings[propertyId];
        for (uint256 i = 0; i < bookingIds.length; i++) {
            Booking memory existing = sBookings[bookingIds[i]];
            if (
                existing.active &&
                checkInDate < existing.checkOutDate &&
                checkOutDate > existing.checkInDate
            ) {
                return false;
            }
        }
        return true;
    }
}