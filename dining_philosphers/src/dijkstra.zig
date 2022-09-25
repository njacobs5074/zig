// Implementation of the Dining Philosophers' problem
// Based on https://en.wikipedia.org/wiki/Dining_philosophers_problem#Dijkstra's_solution

const std = @import("std");

const PhilosopherState = enum { THINKING, HUNGRY, EATING };

// Any number of philosophers should work so long as N is odd and >= 3.
const NUM_PHILOSOPHERS = 5;
const NUM_DINNER_COURSES = 7;

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
    mutex: std.Thread.Mutex = std.Thread.Mutex{},
    rand: *std.rand.Random = undefined,
    numCoursesEaten: u8 = 0,

    fn init(i: usize, rand: *std.rand.Random) Philosopher {
        return Philosopher{ .i = i, .rand = rand };
    }

    fn isDoneEating(self: *Philosopher) bool {
        return self.state == PhilosopherState.THINKING and self.numCoursesEaten >= NUM_DINNER_COURSES - 1;
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
            self.numCoursesEaten += 1;
            print("+++ Philosopher #{d}: Eating course #{d}\n", .{ self.i, self.numCoursesEaten });
            self.semaphore.post();
        }
    }

    fn takeForks(self: *Philosopher) void {
        self.mutex.lock();

        self.state = PhilosopherState.HUNGRY;
        print("+++ Philosopher #{d} is hungry...\n", .{self.i});

        self.tryEating();
        self.mutex.unlock();
        self.semaphore.wait();
    }

    fn releaseForks(self: *Philosopher) void {
        self.mutex.lock();

        self.state = PhilosopherState.THINKING;
        self.left.tryEating();
        self.right.tryEating();
        self.mutex.unlock();

        print("<<< Philosopher #{d} put down their forks\n", .{self.i});
    }

    fn think(self: *Philosopher) void {
        var duration = self.rand.intRangeAtMost(usize, 2, 5);
        print("... Philosopher #{d} thinks for {d} seconds...\n", .{ self.i, duration });

        sleepSeconds(duration);
    }

    fn eat(self: *Philosopher) void {
        var duration = self.rand.intRangeAtMost(usize, 2, 5);
        print(">>> Philosopher #{d} eats for {d} seconds...\n", .{ self.i, duration });

        sleepSeconds(duration);
    }
    
    fn philosophize(philosopher: *@This(), waitLock: *std.Thread.ResetEvent, dinnerDoneLock: *std.Thread.Semaphore) void {
        waitLock.wait();
        while (!philosopher.isDoneEating()) {
            philosopher.think();
            philosopher.takeForks();
            philosopher.eat();
            philosopher.releaseForks();
        }
        print("*** Philosopher #{d} is done with dinner.\n", .{philosopher.i});
        dinnerDoneLock.post();
    }
};

fn spawnPhilosopher(philosopher: *Philosopher, waitLock: *std.Thread.ResetEvent, dinnerDoneLock: *std.Thread.Semaphore) !std.Thread {
    var t = std.Thread.spawn(
        std.Thread.SpawnConfig{}, 
        Philosopher.philosophize, 
        .{ philosopher, waitLock, dinnerDoneLock });

    return t;
}

fn leftNeighbor(i: usize, n: usize) usize {
    return (i + n - 1) % n;
}

fn rightNeighbor(i: usize, n: usize) usize {
    return (i + 1) % n;
}

fn allDone(philosophers: *[NUM_PHILOSOPHERS]Philosopher) bool {
    var f = true;
    for (philosophers) |*p| {
        if (!p.isDoneEating()) {
            f = false;
            break;
        }
    }
    return f;
}

pub fn main() !void {
    print("Dining philosophers\n", .{});

    var rand = makeRandom();
    var waitLock = std.Thread.ResetEvent{};
    var dinnerDoneLock = std.Thread.Semaphore{ .permits = NUM_PHILOSOPHERS };
    var philosophers: [NUM_PHILOSOPHERS]Philosopher = undefined;
    for (philosophers) |*p, i| {
        p.* = Philosopher.init(i, &rand);
    }

    for (philosophers) |*p, i| {
        p.setNeighbors(&philosophers[leftNeighbor(i, philosophers.len)], &philosophers[rightNeighbor(i, philosophers.len)]);
    }

    var threads: [NUM_PHILOSOPHERS]std.Thread = undefined;
    for (philosophers) |*p, i| {
        threads[i] = spawnPhilosopher(p, &waitLock, &dinnerDoneLock) catch |err| {
            print("Failed to spawn philosopher {d} - {}\n", .{ i, err });
            return err;
        };
    }

    // Signal that dinner can begin
    waitLock.set();

    while (!allDone(&philosophers)) {
        dinnerDoneLock.wait();
    }
    inline for (threads) |t| {
        t.join();
    }

    print("Dinner is done!\n", .{});
}

fn makeRandom() std.rand.Random {
    var seed = @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()));
    var prng = std.rand.DefaultPrng.init(seed);
    return prng.random();
}
