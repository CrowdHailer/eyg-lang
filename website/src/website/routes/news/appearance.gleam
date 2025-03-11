import gleam/time/calendar.{Date}

pub type Appearance {
  Podcast(episode: String, link: String, series: String, aired: calendar.Date)
  Meetup(name: String, title: String, video: String, date: calendar.Date)
  Conference(
    name: String,
    title: String,
    lightning: Bool,
    video: String,
    date: calendar.Date,
  )
}

pub fn apperances() {
  [
    Conference(
      name: "Functional Conf",
      title: "Eat your greens a philosophy for language design",
      lightning: False,
      video: "https://www.youtube.com/watch?v=bzUXK5VBbXc",
      date: Date(2025, calendar.January, 24),
    ),
    // https://2024.splashcon.org/home/live-2024
    Conference(
      name: "SPLASH",
      title: "EYG a predictable, and useful, programming language",
      lightning: True,
      video: "https://www.youtube.com/live/4GOeYylCMJI?si=_CX3LkPtt9Xgh7g4&t=28179",
      date: Date(2024, calendar.October, 21),
    ),
    Conference(
      name: "Code BEAM Europe",
      title: "Explaining Effects and Effect Handlers with EYG",
      lightning: True,
      video: "https://www.youtube.com/watch?v=DiehtDWF8fU",
      date: Date(2024, calendar.October, 14),
    ),
    Meetup(
      name: "Func Prog Sweden",
      title: "EYG a predictable, and useful, programming language",
      // https://www.meetup.com/func-prog-sweden/events/301458867/
      video: "https://www.youtube.com/watch?v=dh3sdHWQ2Ms",
      date: Date(2024, calendar.October, 8),
    ),
    Podcast(
      episode: "The EYG Language",
      link: "https://pod.link/1602572955/episode/3b8dfc7a1943a743a462775673090a71",
      series: "Software Unscripted",
      aired: Date(2024, calendar.November, 17),
    ),
    Podcast(
      episode: "Building A Programming Language From Its Core",
      link: "https://pod.link/developer-voices/episode/e47720e8c6dc3d16603b53081bde0cb1",
      series: "Developer voices",
      aired: Date(2024, calendar.August, 07),
    ),
  ]
}
