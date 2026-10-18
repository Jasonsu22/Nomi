import Foundation

enum SampleMeetings {
    static func make(now: Date = .now) -> [Meeting] {
        [
            meeting(
                title: "操作系统 · 进程调度",
                startedAt: today(minutesAgo: 80, now: now),
                duration: 48 * 60,
                paragraphs: [
                    spoken(
                        id: 1,
                        openedAt: 0,
                        pairs: [
                            (
                                "进程调度要解决的是，很多程序同时想用 CPU 时，先让谁跑。",
                                "Process scheduling decides which program gets the CPU when many want it at once."
                            ),
                            (
                                "一个进程把时间片用完，或者自己让出处理器，调度器就再挑下一个。",
                                "When a process uses up its time slice, or yields, the scheduler picks the next one."
                            ),
                        ]
                    ),
                    spoken(
                        id: 2,
                        openedAt: 42,
                        pairs: [
                            (
                                "挑的办法可以很简单，比如先来先服务。",
                                "The policy can be as simple as first come, first served."
                            ),
                            (
                                "也可以按优先级，让交互式的程序先动起来，用户才觉得机器有反应。",
                                "It can also use priority, so interactive programs move first and the machine feels responsive."
                            ),
                        ]
                    ),
                ]
            ),
            meeting(
                title: "线性代数 · 特征值",
                startedAt: today(minutesAgo: 26, now: now),
                duration: 51 * 60,
                paragraphs: [
                    spoken(
                        id: 1,
                        openedAt: 0,
                        pairs: [
                            (
                                "特征值描述的是，一个矩阵把某个方向拉长或缩短了多少。",
                                "An eigenvalue describes how much a matrix stretches or shrinks a direction."
                            ),
                            (
                                "沿着特征向量的方向，变换只改变长度，不改变方向。",
                                "Along an eigenvector, the transform changes the length and leaves the direction alone."
                            ),
                        ]
                    ),
                ]
            ),
            meeting(
                title: "计算机网络 · 拥塞控制",
                startedAt: yesterday(hour: 21, minute: 40, now: now),
                duration: 36 * 60,
                paragraphs: [
                    spoken(
                        id: 1,
                        openedAt: 0,
                        pairs: [
                            (
                                "拥塞控制是发送方自己放慢速度，免得把中间的路由器撑满。",
                                "Congestion control is the sender slowing itself down so it does not fill the routers in between."
                            ),
                            (
                                "丢包被当成网络忙的信号，窗口就缩小，过一会儿再试着长大。",
                                "Packet loss is treated as a sign that the network is busy, so the window shrinks and later tries to grow again."
                            ),
                        ]
                    ),
                ]
            ),
        ]
    }

    private static func meeting(
        title: String,
        startedAt: Date,
        duration: TimeInterval,
        paragraphs: [Paragraph]
    ) -> Meeting {
        Meeting(
            id: UUID(),
            title: title,
            startedAt: startedAt,
            duration: duration,
            source: .microphone,
            sourceLanguage: "zh",
            targetLanguage: "en",
            paragraphs: paragraphs,
            isLive: false
        )
    }

    private static func spoken(id: Int, openedAt: TimeInterval, pairs: [(String, String)]) -> Paragraph {
        var cursor = openedAt
        let commits = pairs.enumerated().map { offset, pair in
            let end = cursor + 6
            let commit = Commit(id: id * 100 + offset, source: pair.0, translation: pair.1, start: cursor, end: end)
            cursor = end
            return commit
        }
        return Paragraph(id: id, openedAt: openedAt, commits: commits, tail: "", closed: true)
    }

    private static func today(minutesAgo: Double, now: Date) -> Date {
        let candidate = now.addingTimeInterval(-minutesAgo * 60)
        if Calendar.current.isDateInToday(candidate) { return candidate }
        return Calendar.current.startOfDay(for: now).addingTimeInterval(min(minutesAgo, 40) * 60)
    }

    private static func yesterday(hour: Int, minute: Int, now: Date) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute
        return Calendar.current.date(from: parts) ?? day
    }
}
