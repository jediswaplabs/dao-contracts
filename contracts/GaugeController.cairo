%lang starknet
%builtins pedersen range_check


// @title Gauge Controller
// @author Mesh Finance
// @license MIT
// @notice Controls liquidity gauges and the issuance of coins through the gauges

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import assert_not_zero, assert_le, assert_lt, unsigned_div_rem
from starkware.cairo.common.uint256 import (
    Uint256, uint256_add, uint256_sub, uint256_mul, uint256_unsigned_div_rem, uint256_eq, uint256_le, uint256_lt, uint256_check
)
from starkware.starknet.common.syscalls import get_block_timestamp

const WEEK = 604800;
const WEIGHT_VOTE_DELAY = 10 * 86400;
const MULTIPLIER = 10 ** 18;

//
// Structs
//
struct Point{
    bias: felt,
    slope: felt,
}

struct VotedSlope{
    slope: felt,
    power: felt,
    end: felt,
}

@contract_interface
namespace VotingEscrow{
    func get_last_user_slope(address: felt) -> (slope: felt){
    }
    
    func locked__end(address: felt) -> (end_ts: felt){
    }
}

//
// Events
//

@event
func CommitOwnership(admin: felt) {
}

@event
func ApplyOwnership(admin: felt) {
}

@event
func AddType(name: felt, type_id: felt) {
}

@event
func NewTypeWeight(type_id: felt, time: felt, weight: felt, total_weight: felt) {
}

@event
func NewGaugeWeight(gauge_address: felt, time: felt, weight: felt, total_weight: felt) {
}

@event
func VoteForGauge(time: felt, user: felt, gauge_address: felt, weight: felt) {
}

@event
func NewGauge(address: felt, gauge_type: felt, weight: felt) {
}

//
// Storage
//

// @notice Admin: Can and will be a smart contract
@storage_var
func _admin() -> (admin: felt) {
}

// @notice Admin: Can and will be a smart contract
@storage_var
func _future_admin() -> (future_admin: felt) {
}

// @notice ERC20MESH token
@storage_var
func _token() -> (token: felt) {
}

// @notice Voting Escrow
@storage_var
func _voting_escrow() -> (voting_escrow: felt) {
}

// @notice Gauge types. All numbers are "fixed point" on the basis of 1e18
@storage_var
func _n_gauge_types() -> (n_gauge_types: felt) {
}

// @notice Gauge numbers. All numbers are "fixed point" on the basis of 1e18
@storage_var
func _n_gauges() -> (n_gauges: felt) {
}

// @notice Gauge type to names. All numbers are "fixed point" on the basis of 1e18
// @param type Type of gauge
@storage_var
func _gauge_type_names(type: felt) -> (names: felt) {
}

// @notice Gauges. Needed for enumeration
// @param gauge_id Gauge ID
@storage_var
func _gauges(gauge_id: felt) -> (gauge: felt) {
}

// @notice We increment values by 1 prior to storing them here so we can rely on a value of zero as meaning the gauge has not been set
// @param address Gauge address
@storage_var
func _gauge_types(address: felt) -> (type: felt) {
}

// @notice Mapping of user -> gauge_addr -> VotedSlope
// @param user User address
// @param gauge_address Gauge address
@storage_var
func _vote_user_slopes(user: felt, gauge_address: felt) -> (voted_slope: VotedSlope) {
}

// @notice Total vote power used by user
// @param user User address
@storage_var
func _vote_user_power(user: felt) -> (power: felt) {
}

// @notice Last user vote's timestamp for each gauge address
// @param user User address
// @param gauge_address Gauge address
@storage_var
func _last_user_vote(user: felt, gauge_address: felt) -> (power: felt) {
}

// Past and scheduled points for gauge weight, sum of weights per type, total weight
// Point is for bias+slope
// changes_* are for changes in slope
// time_* are for the last change timestamp
// timestamps are rounded to whole weeks

// @notice Mapping of gauge_addr -> time -> Point
// @param gauge_address Gauge address
// @param time Time for last change timestamp
@storage_var
func _points_weight(gauge_address: felt, time: felt) -> (point: Point) {
}

// @notice Mapping of gauge_addr -> time -> slope
// @param gauge_address Gauge address
// @param time Time for last change timestamp
@storage_var
func _changes_weight(gauge_address: felt, time: felt) -> (slope: felt) {
}

// @notice Mapping of gauge to time weight
// @param gauge_address Gauge address
@storage_var
func _time_weight(gauge_address: felt) -> (time_weight: felt){
}

// @notice Mapping of type_id -> time -> Point
// @param type_id Type ID
// @param time Time for last change timestamp
@storage_var
func _points_sum(type_id: felt, time: felt) -> (point: Point) {
}

// @notice Mapping of type_id -> time -> slope
// @param type_id Type ID
// @param time Time for last change timestamp
@storage_var
func _changes_sum(type_id: felt, time: felt) -> (slope: felt) {
}

// @notice Mapping of type_id -> last scheduled time (next week)
// @param type_id Type ID
@storage_var
func _time_sum(type_id: felt) -> (sum: felt){
}

// @notice Mapping of time -> total weight
// @param time Time for last change timestamp
@storage_var
func _points_total(time: felt) -> (total_weight: felt) {
}

// @notice Last scheduled time
@storage_var
func _time_total() -> (time_total: felt){
}

// @notice Mapping of type_id -> time -> type weight
// @param type_id Type ID
// @param time Time for last change timestamp
@storage_var
func _points_type_weight(type_id: felt, time: felt) -> (weight: felt) {
}

// @notice Mapping of type_id -> last scheduled time (next week)
// @param type_id Type ID
@storage_var
func _time_type_weight(type_id: felt) -> (weight: felt) {
}

//
// Constructor
//

// @notice Contract constructor
// @param token `ERC20MESH` contract address
// @param voting_escrow `VotingEscrow` contract address
@constructor
func constructor{
        syscall_ptr : felt*, 
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        token: felt,
        voting_escrow: felt
    ) {
    alloc_locals;

    assert_not_zero(token);
    assert_not_zero(voting_escrow);

    let (sender) = get_caller_address();
    _admin.write(sender);
    _token.write(token);
    _voting_escrow.write(voting_escrow);
    let (current_timestamp) = get_block_timestamp();
    // Locktime is rounded down to weeks
    let (current_timestamp_rounded, _) = unsigned_div_rem(current_timestamp, WEEK);
    _time_total.write(current_timestamp_rounded * WEEK);
    
    return ();
}

//
// Getters
//

// @notice Admin
// @return admin Admin address
@view
func admin{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (admin: felt) {
    let (admin) = _admin.read();
    return (admin=admin);
}

// @notice Future Admin
// @return future_admin Future Admin address
@view
func future_admin{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (future_admin: felt) {
    let (future_admin) = _future_admin.read();
    return (future_admin=future_admin);
}

// @notice Voting Escrow
// @return voting_escrow Voting Escrow address
@view
func voting_escrow{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (voting_escrow: felt) {
    let (voting_escrow) = _voting_escrow.read();
    return (voting_escrow=voting_escrow);
}

// @notice Token
// @return token Token address
@view
func token{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (token: felt) {
    let (token) = _token.read();
    return (token=token);
}

// @notice N gauge types
// @return n_types Number of gauge types
@view
func n_gauge_types{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (n_gauge_types: felt) {
    let (n_gauge_types) = _n_gauge_types.read();
    return (n_gauge_types=n_gauge_types);
}

// @notice N gauges
// @return n_gauges Number of gauges
@view
func n_gauges{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (n_gauges: felt) {
    let (n_gauges) = _n_gauges.read();
    return (n_gauges=n_gauges);
}

// @notice Gauge type name
// @param type_id Type ID
// @return name Gauge type name
@view
func gauge_type_names{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt) -> (name: felt) {
    let (name) = _gauge_type_names.read(type_id);
    return (name=name);
}

// @notice Gauges
// @param gauge_id Gauge ID
// @return gauge Gauge address
@view
func gauges{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_id: felt) -> (gauge: felt) {
    let (gauge) = _gauges.read(gauge_id);
    return (gauge=gauge);
}

// @notice Get gauge type for address
// @param _addr Gauge address
// @return Gauge type id
@view
func gauge_types{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt) -> (gauge_type: felt) {
    let (gauge_type) = _gauge_types.read(gauge_address);
    assert_not_zero(gauge_type);
    return (gauge_type=gauge_type - 1);
}

// @notice Mapping of user -> gauge_addr -> VotedSlope
// @param user User address
// @param gauge_addr Gauge address
@view
func vote_user_slopes{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (user: felt, gauge_addr: felt) -> (voted_slope: VotedSlope) {
    let (voted_slope) = _vote_user_slopes.read(user, gauge_addr);
    return (voted_slope=voted_slope);
}

// @notice Total vote power used by user
// @param user User address
@view
func vote_user_power{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (user: felt) -> (total: felt) {
    let (total) = _vote_user_power.read(user);
    return (total=total);
}

// @notice Last user vote's timestamp for each gauge address
// @param user User address
// @param gauge_address Gauge address
@view
func last_user_vote{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (user: felt, gauge_address: felt) -> (timestamp: felt) {
    let (timestamp) = _last_user_vote.read(user, gauge_address);
    return (timestamp=timestamp);
}

// @notice Mapping of gauge_addr -> time -> Point
// @param gauge_address Gauge address
// @param time Time for last change timestamp
@view
func points_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt, time: felt) -> (point: Point) {
    let (point) = _points_weight.read(gauge_address, time);
    return (point=point);
}

// @notice Mapping of gauge_addr -> time -> slope
// @param gauge_address Gauge address
// @param time Time for last change timestamp
@view
func changes_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt, time: felt) -> (slope: felt) {
    let (slope) = _changes_weight.read(gauge_address, time);
    return (slope=slope);
}

// @notice Mapping of gauge to time weight
// @param gauge_address Gauge address
@view
func time_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (gauge_address: felt) -> (time_weight: felt) {
    let (time_weight) = _time_weight.read(gauge_address);
    return (time_weight=time_weight);
}

// @notice Mapping of type_id -> time -> Point
// @param type_id Type ID
// @param time Time for last change timestamp
@view
func points_sum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt, time: felt) -> (point: Point) {
    let (point) = _points_sum.read(type_id, time);
    return (point=point);
}

// @notice Mapping of type_id -> time -> slope
// @param type_id Type ID
// @param time Time for last change timestamp
@view
func changes_sum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt, time: felt) -> (slope: felt) {
    let (slope) = _changes_sum.read(type_id, time);
    return (slope=slope);
}

// @notice Mapping of type_id -> last scheduled time (next week)
// @param type_id Type ID
@view
func time_sum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt) -> (time: felt) {
    let (time) = _time_sum.read(type_id);
    return (time=time);
}

// @notice Mapping of time -> total weight
// @param time Time for last change timestamp
@view
func points_total{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (time: felt) -> (weight: felt) {
    let (weight) = _points_total.read(time);
    return (weight=weight);
}

// @notice Last scheduled time
@view
func time_total{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () -> (time: felt) {
    let (time) = _time_total.read();
    return (time=time);
}

// @notice Mapping of type_id -> time -> type weight
// @param type_id Type ID
// @param time Time for last change timestamp
@view
func points_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt, time: felt) -> (weight: felt) {
    let (weight) = _points_type_weight.read(type_id, time);
    return (weight=weight);
}

// @notice Mapping of type_id -> last scheduled time (next week)
// @param type_id Type ID
@view
func time_type_weight{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (type_id: felt) -> (time: felt) {
    let (time) = _time_type_weight.read(type_id);
    return (time=time);
}

//
// Externals
//

// @notice Transfer ownership of GaugeController to `address`
// @param addr Address to have ownership transferred to
@external
func commit_transfer_ownership{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } (addr: felt) {
    alloc_locals;

    let (sender) = get_caller_address();
    let (admin) = _admin.read();
    assert sender = admin;
    assert_not_zero(addr);
    _future_admin.write(addr);

    CommitOwnership.emit(addr);

    return ();
}

// @notice Apply pending ownership transfer
@external
func apply_transfer_ownership{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    } () {
    alloc_locals;

    let (sender) = get_caller_address();
    let (future_admin) = _future_admin.read();
    assert sender = future_admin;
    _admin.write(future_admin);
    _future_admin.write(0);

    ApplyOwnership.emit(future_admin);

    return ();
}

//
// Internal
//

// @notice Fill historic type weights week-over-week for missed checkins. Use recursion
// and return the type weight for the future week
// @param gauge_type Gauge type id
// @return Type weight
// func _get_type_weight{
//         syscall_ptr : felt*,
//         pedersen_ptr : HashBuiltin*,
//         range_check_ptr
//     } () {
//     alloc_locals;

//     let (t) = _time_type_weight.read(type_id);

    
// }

