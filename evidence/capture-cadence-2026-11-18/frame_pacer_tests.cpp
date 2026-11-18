#include "frame_pacer.hpp"
#include <array>
#include <chrono>
#include <iostream>
#include <stdexcept>

using namespace std::chrono;
using reims_stream::advance_capture_deadline;
using Clock = steady_clock;
void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}
int main() {
    const Clock::time_point start{};
    const auto interval = nanoseconds(16666666);
    // At 60 fps, a 10 ms copy must not turn the period into 26.7 ms.
    for (auto work : {0ms, 1ms, 10ms, 16ms}) {
        auto deadline = start;
        for (int i = 0; i < 600; ++i) {
            deadline = advance_capture_deadline(deadline, interval, deadline + work);
        }
        require(deadline == start + 600 * interval, "copy work changed requested cadence");
    }
    auto deadline = start;
    const std::array work{2ms, 12ms, 1ms, 15ms, 4ms};
    for (int i = 0; i < 600; ++i) {
        deadline = advance_capture_deadline(deadline, interval, deadline + work[i % work.size()]);
    }
    require(deadline == start + 600 * interval, "variable copy work accumulated drift");
    require(advance_capture_deadline(start, interval, start + interval) == start + interval,
            "on-time deadline was skipped");
    const auto late = start + 100ms;
    const auto recovered = advance_capture_deadline(start, interval, late);
    require(recovered >= late && recovered - late <= interval, "missed deadlines cause catch-up bursts");
    require((recovered - start) % interval == 0ns, "recovery lost the absolute cadence");
    const auto timed_out = advance_capture_deadline(start, interval, start + 500ms);
    require(timed_out >= start + 500ms && timed_out <= start + 500ms + interval,
            "capture timeout did not recover to a future slot");
    std::cout << "PASS: fixed/variable copy cost, exact deadline, missed slots, timeout recovery\n";
}
