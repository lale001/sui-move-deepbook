#[allow(unused_imports)]
module car_booking::car_booking {

    // Imports
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::Coin;
    use sui::clock::Clock;
    use sui::object::{self, UID, ID};
    use sui::balance::{self, Balance};
    use sui::tx_context::TxContext;
    use sui::table::Table;

    // Errors
    const EInsufficientFunds: u64 = 1;
    const EInvalidCoin: u64 = 2;
    const ENotCustomer: u64 = 3;
    const EInvalidCar: u64 = 4;
    const ENotCompany: u64 = 5;
    const EInvalidCarBooking: u64 = 6;

    // CarBooking Company 

    pub struct CarCompany pub key {
        id: UID,
        name: String,
        car_prices: Table<ID, u64>, // car_id -> price
        balance: Balance<SUI>,
        memos: Table<ID, CarMemo>, // car_id -> memo
        company: address
    }

    // Customer

    pub struct Customer pub key {
        id: UID,
        name: String,
        customer: address,
        company_id: ID,
        balance: Balance<SUI>,
    }

    // CarMemo

    pub struct CarMemo pub key, store {
        id: UID,
        car_id: ID,
        rental_fee: u64,
        company: address 
    }

    // Car

    pub struct Car pub key {
        id: UID,
        name: String,
        car_type : String,
        company: address,
        available: bool,
    }

    // Record of Car Booking

    pub struct BookingRecord pub key, store {
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
        let company = CarCompany {
            id: object::new(ctx),
            name: name,
            car_prices: Table::new(ctx),
            balance: Balance::zero(),
            memos: Table::new(ctx),
            company: TxContext::sender(ctx)
        };

        transfer::share_object(company);
    }

    // Create a new Customer object

    pub fun create_customer(ctx: &mut TxContext, name: String, company_address: address) {
        let company_id_: ID = object::id_from_address(company_address);
        let customer = Customer {
            id: object::new(ctx),
            name: name,
            customer: TxContext::sender(ctx),
            company_id: company_id_,
            balance: Balance::zero(),
        };

        transfer::share_object(customer);
    }

    // Create a memo for a car

    pub fun create_car_memo(
        company: &mut CarCompany,
        rental_fee: u64,
        car_name: String,
        car_type: String,
        ctx: &mut TxContext
    ) -> CarMemo {
        assert!(company.company == TxContext::sender(ctx), ENotCompany);
        let car = Car {
            id: object::new(ctx),
            name: car_name,
            car_type: car_type,
            company: company.company,
            available: true
        };
        let memo = CarMemo {
            id: object::new(ctx),
            car_id: object::uid_to_inner(&car.id),
            rental_fee: rental_fee,
            company: company.company
        };

        Table::add(&mut company.memos, object::uid_to_inner(&car.id), memo.clone());

        memo
    }

    // Book a car

    pub fun book_car(
        company: &mut CarCompany,
        customer: &mut Customer,
        car: &mut Car,
        car_memo_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ) -> Coin<SUI> {
        assert!(company.company == TxContext::sender(ctx), ENotCompany);
        assert!(customer.company_id == object::id_from_address(company.company), ENotCustomer);
        assert!(Table::contains(&company.memos, car_memo_id), EInvalidCarBooking);
        assert!(car.company == company.company, EInvalidCar);
        assert!(car.available, EInvalidCar);
        let car_id = &car.id;
        let memo = Table::borrow(&company.memos, car_memo_id);

        let customer_id = object::uid_to_inner(&customer.id);
        
        let rental_fee = memo.rental_fee;
        let booking_time = Clock::timestamp_ms(clock);
        let booking_record = BookingRecord {
            id: object::new(ctx),
            customer_id: customer_id,
            car_id: object::uid_to_inner(car_id),
            customer: customer.customer,
            company: company.company,
            paid_fee: rental_fee,
            rental_fee: rental_fee,
            booking_time: booking_time
        };

        transfer::public_freeze_object(booking_record);
        // deduct the rental fee from the customer balance and add it to the company balance
        assert!(rental_fee <= balance::value(&customer.balance), EInsufficientFunds);
        let amount_to_pay = coin::take(&mut customer.balance, rental_fee, ctx);
        assert!(coin::value(&amount_to_pay) > 0, EInvalidCoin);

        transfer::public_transfer(amount_to_pay, company.company);

        amount_to_pay
    }

    // Customer adding funds to their account

    pub fun top_up_customer_balance(
        customer: &mut Customer,
        amount: Coin<SUI>,
        ctx: &mut TxContext
    ){
        assert!(customer.customer == TxContext::sender(ctx), ENotCustomer);
        balance::join(&mut customer.balance, coin::into_balance(amount));
    }

    // add the Payment fee to the company balance

    pub fun top_up_company_balance(
        company: &mut CarCompany,
        customer: &mut Customer,
        car: &mut Car,
        car_memo_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ){
        // Can only be called by the customer
        assert!(customer.customer == TxContext::sender(ctx), ENotCustomer);
        let _ = book_car(company, customer, car, car_memo_id, clock, ctx);
    }

    // Get the balance of the company

    pub fun get_company_balance(company: &CarCompany) -> &Balance<SUI> {
        &company.balance
    }

    // Company can withdraw the balance

    pub fun withdraw_funds(
        company: &mut CarCompany,
        amount: u64,
        ctx: &mut TxContext
    ){
        assert!(company.company == TxContext::sender(ctx), ENotCompany);
        assert!(amount <= balance::value(&company.balance), EInsufficientFunds);
        let amount_to_withdraw = coin::take(&mut company.balance, amount, ctx);
        transfer::public_transfer(amount_to_withdraw, company.company);
    }
    
    // Transfer the Ownership
