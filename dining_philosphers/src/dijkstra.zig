// Implementation of the Dining Philosophers' problem
// Based on https://en.wikipedia.org/wiki/Dining_philosophers_problem#Dijkstra's_solution

const std = @import("std");

const PhilosopherState = enum { THINKING, HUNGRY, EATING };
const NUM_PHILOSOPHERS = 5;
var runLock = std.Thread.ResetEvent{};

var printMutex = std.Thread.Mutex{};
fn print(comptime fmt: []const u8, args: anytype) void {
    printMutex.lock();
    defer printMutex.unlock();

    std.debug.print(fmt, args);
}

fn sleepSeconds(seconds: u64) void {
    std.time.sleep(seconds * 1_000_000_000);
}

const Philosopher = struct {
    i: usize,
    state: PhilosopherState = PhilosopherState.THINKING,
    left: *Philosopher = undefined,
    right: *Philosopher = undefined,
    semaphore: std.Thread.Semaphore = std.Thread.Semaphore{},
    mutex: *std.Thread.Mutex,
    rand: *std.rand.Random,
    done: bool = false,

    fn init(i: usize, mutex: *std.Thread.Mutex, rand: *std.rand.Random) Philosopher {
        return Philosopher{
            .i = i,
            .mutex = mutex,
            .rand = rand
        };
    }

    fn setNeighbors(self: *Philosopher, left: *Philosopher, right: *Philosopher) void {
        self.left = left;
        self.right = right;
    }

    fn tryEating(self: *Philosopher) void {
        if (self.state == PhilosopherState.HUNGRY and 
            self.left.state != PhilosopherState.EATING and
            self.right.state != PhilosopherState.EATING) {
            self.state = PhilosopherState.EATING;
            self.semaphore.post();
        } else {
            print("{d}: Forks not available! {d}={} {d}={}\n", .{self.i, self.left.i, self.left.state, self.right.i, self.right.state});
        }
    }

    fn think(self: *Philosopher) void {
        var duration = self.rand.intRangeAtMost(usize, 2, 5);
        print("{d} thinks for {d} seconds...\n", .{self.i, duration});

        sleepSeconds(duration);
    }

    fn takeForks(self: *Philosopher) void {
        self.mutex.lock();

        self.state = PhilosopherState.HUNGRY;
        print("{d} is hungry...\n", .{self.i});

        self.tryEating();
        self.mutex.unlock();
        self.semaphore.wait();
    }

    fn releaseForks(self: *Philosopher) void {
        self.mutex.lock();

        self.state = PhilosopherState.THINKING;
        self.left.tryEating();
        self.right.tryEating();
        print("{d} released forks\n", .{self.i});
        self.mutex.unlock();
    }


    fn eat(self: *Philosopher) void {
        var duration = self.rand.intRangeAtMost(usize, 2, 5);
        print("*** {d} eats for {d} seconds...\n", .{self.i, duration});

        sleepSeconds(duration);
    }

};

fn philosophize(philosopher: *Philosopher) void {
    runLock.wait();
    while (!philosopher.done) {
        philosopher.think();
        philosopher.takeForks();
        philosopher.eat();
        philosopher.releaseForks();
    }
}

fn spawnPhilosopher(philosopher: *Philosopher) std.Thread.SpawnError!std.Thread {
    return std.Thread.spawn(std.Thread.SpawnConfig{}, philosophize, .{ philosopher }) catch @panic("Failed to spawn thread");
}

fn leftNeighbor(i: usize, n: usize) usize {
    return (i + n - 1) % n;
}

fn rightNeighbor(i: usize, n: usize) usize {
    return (i + 1) % n;
}

pub fn main() !void {
    var rand = makeRandom();
    var mutex = std.Thread.Mutex{};

    print("Dining philosophers\n", .{});
    var philosophers: [NUM_PHILOSOPHERS]Philosopher = undefined;
    for (philosophers) |*p, i| {
        p.* = Philosopher.init(i, &mutex, &rand);
    }

    for (philosophers) |*p, i| {
        p.setNeighbors(
            &philosophers[leftNeighbor(i, philosophers.len)], 
            &philosophers[rightNeighbor(i, philosophers.len)]
        );
    }


    var threads: [philosophers.len]std.Thread = undefined;
    for (philosophers) |*p, i| {
        threads[i] = spawnPhilosopher(p) catch |err| {
            print("Failed to spawn philosopher {d} - {}\n", .{i, err});
            return err;
        };
    }

    runLock.set();

    for (threads) |t| {
        t.join();
    }

    print("Dinner is over!\n", .{});
}

fn makeRandom() std.rand.Random {
    var seed = @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()));
    var prng = std.rand.DefaultPrng.init(seed);
    return prng.random();
}
