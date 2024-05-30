module car_booking::main {
    use std::string::{String};
    use sui::transfer;
    use sui::object::{Self, UID, ID};
    use sui::url::{Self, Url};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::object_table::{Self, ObjectTable};
    use sui::dynamic_field as df;
    use sui::dynamic_object_field as dof;
    use sui::event;
    use sui::tx_context::{Self, TxContext, sender};

    const ERROR_NOT_THE_OWNER: u64 = 0;
    const ERROR_INSUFFICIENT_FUNDS: u64 = 1;

    struct Car has key, store {
        id: UID,
        title: String,
        artist: address,
        year: u64,
        price: u64,
        img_url: Url,
        description: String,
        for_sale: bool,
    }

    struct CarCompany has key, store {
        id: UID,
        owner: address,
        balance: Balance<SUI>,
        counter: u64,
        cars: ObjectTable<u64, Car>, // changed to lowercase
    }

    struct CarCompanyCap has key, store {
        id: UID,
        for: ID
    }

    struct Listing has store, copy, drop { id: ID, is_exclusive: bool }

    struct Item has store, copy, drop { id: ID }

    struct CarCreated has copy, drop {
        id: ID,
        artist: address,
        title: String,
        year: u64,
        description: String,
    }

    struct CarUpdated has copy, drop {
        title: String,
        year: u64,
        description: String,
        for_sale: bool,
        price: u64,
    }

    struct CarDeleted has copy, drop {
        car_id: ID, // changed from art_id
        title: String,
        artist: address,
    }

    public fun new(ctx: &mut TxContext) : CarCompanyCap {
        let id_ = object::new(ctx);
        let inner_ = object::uid_to_inner(&id_);
        transfer::share_object(
            CarCompany {
                id: id_,
                owner: sender(ctx),
                balance: balance::zero(),
                counter: 0,
                cars: object_table::new(ctx), // changed to lowercase
            }
        );
        CarCompanyCap {
            id: object::new(ctx),
            for: inner_
        }
    }

    // Function to create Car
    public fun mint(
        title: String,
        img_url: vector<u8>,
        year: u64,
        price: u64,
        description: String,
        ctx: &mut TxContext,
    ) : Car {

        let id = object::new(ctx);
        event::emit(
            CarCreated {
                id: object::uid_to_inner(&id),
                title: title.clone(),
                artist: tx_context::sender(ctx),
                year: year,
                description: description.clone(),
            }
        );

        Car {
            id: id,
            title: title,
            artist: tx_context::sender(ctx),
            year: year,
            img_url: url::new_unsafe_from_bytes(img_url),
            description: description,
            for_sale: true,
            price: price,
        }
    }

    // Function to add Car to CarCompany
    public entry fun list<T: key + store>(
        self: &mut CarCompany,
        cap: &CarCompanyCap,
        item: T,
        price: u64,
    ) {
        assert!(object::id(self) == cap.for, ERROR_NOT_THE_OWNER);
        let id = object::id(&item);
        place_internal(self, item);
        df::add(&mut self.id, Listing { id, is_exclusive: false }, price);
    }

    public fun delist<T: key + store>(
        self: &mut CarCompany, cap: &CarCompanyCap, id: ID
    ) : T {
        assert!(object::id(self) == cap.for, ERROR_NOT_THE_OWNER);
        self.counter = self.counter - 1;
        df::remove_if_exists<Listing, u64>(&mut self.id, Listing { id, is_exclusive: false });
        dof::remove(&mut self.id, Item { id })    
    }

    public fun purchase<T: key + store>(
        self: &mut CarCompany, id: ID, payment: Coin<SUI>
    ): T {
        let price = df::remove<Listing, u64>(&mut self.id, Listing { id, is_exclusive: false });
        let inner = dof::remove<Item, T>(&mut self.id, Item { id });

        self.counter = self.counter - 1;
        assert!(price == coin::value(&payment), ERROR_INSUFFICIENT_FUNDS);
        coin::put(&mut self.balance, payment);
        inner
    }
    
    // Function to Update Car Properties
    public entry fun update(
        car: &mut Car,
        title: String,
        year: u64,
        description: String,
        for_sale: bool,
        price: u64,
    ) {
        car.title = title;
        car.year = year;
        car.description = description;
        car.for_sale = for_sale;
        car.price = price;

        event::emit(
            CarUpdated {
                title: car.title.clone(),
                year: car.year,
                description: car.description.clone(),
                for_sale: car.for_sale,
                price: car.price,
            }
        );
    }

    public fun withdraw(
        self: &mut CarCompany, cap: &CarCompanyCap, amount: u64, ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(object::id(self) == cap.for, ERROR_NOT_THE_OWNER);
        coin::take(&mut self.balance, amount, ctx)
    }
    
    // Function to get the owner of a Car
    public fun get_owner(self: &CarCompany) : address {
        self.owner
    }

    // Function to fetch the Car Information
    public fun get_car_info(self: &CarCompany, id: u64) : (
        String,
        address,
        u64,
        u64,
        Url,
        String,
        bool
    ) {
        let car = object_table::borrow(&self.cars, id); // changed to lowercase
        (
            car.title.clone(),
            car.artist,
            car.year,
            car.price,
            car.img_url.clone(),
            car.description.clone(),
            car.for_sale,
        )
    }

    // Function to delete a Car
    public entry fun delete_car(
        car: Car,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == car.artist, ERROR_NOT_THE_OWNER);
        event::emit(
            CarDeleted {
                car_id: object::uid_to_inner(&car.id),
                title: car.title.clone(),
                artist: car.artist,
            }
        );

        let Car { id, title: _, artist: _, year: _, price: _, img_url: _, description: _, for_sale: _ } = car;
        object::delete(id);
    }

    public fun place_internal<T: key + store>(self: &mut CarCompany, item: T) {
        self.counter = self.counter + 1;
        dof::add(&mut self.id, Item { id: object::id(&item) }, item)
    }
}

// Tests
module car_booking::tests {
    use car_booking::main;
    use std::string::String;
    use sui::url::Url;
    use sui::coin::Coin;
    use sui::sui::SUI;
    use sui::tx_context::TxContext;
    use sui::test_scenario::TestScenario;
    use sui::object::UID;

    public fun run_tests() {
        let ctx = &mut TestScenario::create().create_ctx();

        // Test for creating a new CarCompany
        let cap = main::new(ctx);
        assert!(cap.for != object::ID::zero(), "CarCompanyCap creation failed");

        // Test for minting a new Car
        let img_url = vec![104, 116, 116, 112, 115, 58, 47, 47, 101, 120, 97, 109, 112, 108, 101, 46, 99, 111, 109];
        let car = main::mint(
            String::from("Test Car"),
            img_url,
            2023,
            1000,
            String::from("This is a test car."),
            ctx
        );
        assert!(object::id(&car) != UID::zero(), "Car minting failed");

        // Test for listing a Car
        let car_company = main::CarCompany {
            id: object::new(ctx),
            owner: sui::tx_context::sender(ctx),
            balance: sui::balance::zero(),
            counter: 0,
            cars: sui::object_table::new(ctx),
        };
        main::list(&mut car_company, &cap, car, 1000);

        // Test for fetching Car information
        let car_info = main::get_car_info(&car_company, 0);
        assert!(car_info.0 == "Test Car", "Fetching car information failed");

        // Test for purchasing a Car
        let payment = Coin<SUI>::mint(1000, ctx);
        let purchased_car = main::purchase(&mut car_company, object::id(&car), payment);
        assert!(object::id(&purchased_car) == object::id(&car), "Car purchase failed");

        // Test for updating a Car
        let mut car_to_update = purchased_car;
        main::update(&mut car_to_update, String::from("Updated Car"), 2024, String::from("Updated description"), false, 1500);
        assert!(car_to_update.title == "Updated Car", "Car update failed");

        // Test for deleting a Car
        main::delete_car(car_to_update, ctx);
        assert!(object::id(&car_to_update) == UID::zero(), "Car deletion failed");
    }
}
