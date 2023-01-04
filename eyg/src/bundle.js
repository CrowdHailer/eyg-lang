import {main} from "./atelier/main.mjs"
fetch('/saved/saved.json').then(resp => {
    return resp.text()
  }).then(source => {
    main(source)
  })
