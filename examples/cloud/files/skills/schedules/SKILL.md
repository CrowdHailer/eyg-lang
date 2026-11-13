---
name: schedules
description: How to send yourself messages later, once or on a schedule.
---

`Timeout` sends a message to this conversation once, after a number of milliseconds:

```eyg
perform Timeout({name: "tea", after: 180000, message: "Remind alice her tea is ready."})
```

`Cron` sends a message on a cron schedule, five fields or six with seconds, in UTC:

```eyg
perform Cron({name: "weekly", schedule: "0 9 * * 1", message: "Post the weekly summary."})
```

Cancel either with `perform CancelSchedule("tea")`.
When the message arrives decide whether to post anything.
