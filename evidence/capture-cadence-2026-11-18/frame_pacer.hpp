#pragma once

#include <chrono>

namespace reims_stream {
/**
 * @brief Keep capture on an absolute schedule, including copy and push work.
 * @param previous The deadline used to start the frame that just finished.
 * @param interval Positive requested frame interval.
 * @param finished Time when capture and delivery of the frame finished.
 * @return The next scheduled deadline, skipping expired slots without bursts.
 */
inline std::chrono::steady_clock::time_point advance_capture_deadline(
    std::chrono::steady_clock::time_point previous,
    std::chrono::nanoseconds interval,
    std::chrono::steady_clock::time_point finished) {
    auto next = previous + interval;
    if (next < finished) {
        next += interval * ((finished - next) / interval + 1);
    }
    return next;
}
} // namespace reims_stream
