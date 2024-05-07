#[allow(unused_use)]
module car_booking::car_booking {

   // Imports
   use sui::transfer;
   use sui::sui::SUI;
   use std::string::{Self, String};
   use sui::coin::{Self, Coin};
   use sui::clock::{Self, Clock};
   use sui::object::{Self, UID, ID};
   use sui::balance::{Self, Balance};
   use sui::tx_context::{Self, TxContext};
   use sui::table::{Self, Table};

   // Errors
   const EInsufficientFunds: u64 = 1;
   const EInvalidCoin: u64 = 2;
   const ENotCustomer: u64 = 3;
   const EInvalidCar: u64 = 4;
   const ENotCompany: u64 = 5;
   const EInvalidCarBooking: u64 = 6;
   const EInvalidOwnershipTransfer: u64 = 7;

   // CarBooking Company 

   struct CarCompany has key {
       id: UID,
       name: String,
       car_prices: Table<ID, u64>, // car_id -> price
       balance: Balance<SUI>,
       memos: Table<ID, CarMemo>, // car_id -> memo
       company: address
   }

   // Customer

   struct Customer has key {
       id: UID,
       name: String,
       customer: address,
       company_id: ID,
       balance: Balance<SUI>,
   }

   // CarMemo

   struct CarMemo has key, store {
       id: UID,
       car_id: ID,
       rental_fee: u64,
       company: address 
   }

   // Car

   struct Car has key {
       id: UID,
       name: String,
       car_type: String,
       company: address,
       available: bool,
       current_customer: address
   }

   // Record of Car Booking

   struct BookingRecord has key, store {
       id: UID,
       customer_id: ID,
       car_id: ID,
       customer: address,
       company: address,
       paid_fee: u64,
       rental_fee: u64,
       booking_time: u64
   }

   // Create a new CarCompany object 

   public fun create_company(ctx: &mut TxContext, name: String) {
       assert!(!string::is_empty(&name), EInvalidCompanyName);
       let company = CarCompany {
           id: object::new(ctx),
           name,
           car_prices: table::new<ID, u64>(ctx),
           balance: balance::zero<SUI>(),
           memos: table::new<ID, CarMemo>(ctx),
           company: tx_context::sender(ctx)
       };

       transfer::share_object(company);
   }

   // Create a new Customer object

   public fun create_customer(ctx: &mut TxContext, name: String, company_address: address) {
       assert!(!string::is_empty(&name), EInvalidCustomerName);
       let company_id: ID = object::id_from_address(company_address);
       let customer = Customer {
           id: object::new(ctx),
           name,
           customer: tx_context::sender(ctx),
           company_id,
           balance: balance::zero<SUI>(),
       };

       transfer::share_object(customer);
   }

   // Create a car

   public fun create_car(
       company: &mut CarCompany,
       car_name: String,
       car_type: String,
       ctx: &mut TxContext
   ): Car {
       assert!(company.company == tx_context::sender(ctx), ENotCompany);
       assert!(!string::is_empty(&car_name), EInvalidCarName);
       assert!(!string::is_empty(&car_type), EInvalidCarType);

       let car = Car {
           id: object::new(ctx),
           name: car_name,
           car_type,
           company: company.company,
           available: true,
           current_customer: @0x0
       };

       car
   }

   // Create a memo for a car

   public fun create_car_memo(
       company: &mut CarCompany,
       rental_fee: u64,
       car: &Car,
       ctx: &mut TxContext
   ): CarMemo {
       assert!(company.company == tx_context::sender(ctx), ENotCompany);
       assert!(car.company == company.company, EInvalidCar);

       let memo = CarMemo {
           id: object::new(ctx),
           car_id: object::uid_to_inner(&car.id),
           rental_fee,
           company: company.company
       };

       table::add<ID, CarMemo>(&mut company.memos, object::uid_to_inner(&car.id), memo);

       memo
   }

   // Book a car

   public fun book_car(
       company: &mut CarCompany,
       customer: &mut Customer,
       car: &mut Car,
       memo: &CarMemo,
       clock: &Clock,
       ctx: &mut TxContext
   ): Coin<SUI> {
       assert!(company.company == tx_context::sender(ctx), ENotCompany);
       assert!(customer.company_id == object::id_from_address(company.company), ENotCustomer);
       assert!(car.company == company.company, EInvalidCar);
       assert!(car.available, EInvalidCar);
       assert!(memo.car_id == object::uid_to_inner(&car.id), EInvalidCarBooking);

       let customer_id = object::uid_to_inner(&customer.id);
       let rental_fee = memo.rental_fee;
       let booking_time = clock::timestamp_ms(clock);

       let booking_record = BookingRecord {
           id: object::new(ctx),
           customer_id,
           car_id: object::uid_to_inner(&car.id),
           customer: customer.customer,
           company: company.company,
           paid_fee: rental_fee,
           rental_fee,
           booking_time
       };

       transfer::public_freeze_object(booking_record);

       // Deduct the rental fee from the customer balance and add it to the company balance
       assert!(rental_fee <= balance::value(&customer.balance), EInsufficientFunds);
       let amount_to_pay = coin::take(&mut customer.balance, rental_fee, ctx);
       assert!(coin::value(&amount_to_pay) > 0, EInvalidCoin);

       car.available = false;
       car.current_customer = customer.customer;

       amount_to_pay
   }

   // Update balances

   public fun update_balances(
       company: &mut CarCompany,
       customer: &mut Customer,
       car: &mut Car,
       memo: &CarMemo,
       clock: &Clock,
       ctx: &mut TxContext
   ) {
       assert!(customer.customer == tx_context::sender(ctx), ENotCustomer);
       let amount_to_pay = book_car(company, customer, car, memo, clock, ctx);
       balance::join(&mut company.balance, coin::into_balance(amount_to_pay));
   }

   // Get the balance of the company

   public fun get_company_balance(company: &CarCompany): &Balance<SUI> {
       &company.balance
   }

   // Company can withdraw the balance

   public fun withdraw_funds(
       company: &mut CarCompany,
       amount: u64,
       ctx: &mut TxContext
   ) {
       assert!(company.company == tx_context::sender(ctx), ENotCompany);
       assert!(amount <= balance::value(&company.balance), EInsufficientFunds);
       let amount_to_withdraw = coin::take(&mut company.balance, amount, ctx);
       assert!(balance::value(&company.balance) >= 0, EInsufficientFunds);
       transfer::public_transfer(amount_to_withdraw, company.company);
   }

   // Transfer the Ownership of the car
public entry fun transfer_car_ownership(
       customer: &Customer,
       car: &mut Car,
       ctx: &mut TxContext
   ) {
       assert!(car.current_customer == customer.customer, EInvalidOwnershipTransfer);
       assert!(car.available == false, EInvalidOwnershipTransfer);

       transfer::transfer(car, customer.customer);
   }

   // Customer Returns the car ownership
   // Set the car as available again

   public fun return_car(
       company: &mut CarCompany,
       customer: &Customer,
       car: &mut Car,
       ctx: &mut TxContext
   ) {
       assert!(company.company == tx_context::sender(ctx), ENotCompany);
       assert!(customer.company_id == object::id_from_address(company.company), ENotCustomer);
       assert!(car.company == company.company, EInvalidCar);
       assert!(car.current_customer == customer.customer, EInvalidCarReturn);

       car.available = true;
       car.current_customer = @0x0;
   }

   // Error codes
   const EInvalidCompanyName: u64 = 7;
   const EInvalidCustomerName: u64 = 8;
   const EInvalidCarName: u64 = 9;
   const EInvalidCarType: u64 = 10;
   const EInvalidCarReturn: u64 = 11;
}
