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
        cars: ObjectTable<u64, Car>,
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
        art_id: ID,
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
                cars: object_table::new(ctx),
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
                title: title,
                artist: tx_context::sender(ctx),
                year: year,
                description: description,
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
                title: car.title,
                year: car.year,
                description: car.description,
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
    // Function to get the artist of a Car
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
        let car = object_table::borrow(&self.cars, id);
        (
            car.title,
            car.artist,
            car.year,
            car.price,
            car.img_url,
            car.description,
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
                art_id: object::uid_to_inner(&car.id),
                title: car.title,
                artist: car.artist,
            }
        );
        let Car { id, title:_, artist:_, year:_, price:_, img_url:_, description:_, for_sale:_ } = car;
        object::delete(id);
    }
    public fun place_internal<T: key + store>(self: &mut CarCompany, item: T) {
        self.counter = self.counter + 1;
        dof::add(&mut self.id, Item { id: object::id(&item) }, item)
    }
}