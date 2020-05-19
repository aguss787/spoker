(() => {
    uid = "0bg53i0ZicVYgOcJQXPirRQ1ttR2oq5VATu15JsN1cvBuyRtSp3olSzK3uoJ_HTwKrfa6RjGTTNGVQDICQGiyg=="
    class myWebsocketHandler {
        setupSocket() {
            this.socket = new WebSocket("ws://localhost:8001/ws/room/1")

            this.socket.addEventListener("message", (event) => {
                const pTag = document.createElement("p")
                pTag.innerHTML = event.data

                document.getElementById("main").append(pTag)
            })

            this.socket.addEventListener("close", () => {
                console.log("close")
                this.setupSocket()
            })

            this.socket.addEventListener("open", () => {
                console.log("open")

                this.socket.send(
                    JSON.stringify({
                        type: "init",
                        data: {
                            role: "observer",
                            token: "" + uid
                        },
                    })
                )
            })
        }

        submit(event) {
            event.preventDefault()
            const input = document.getElementById("message")
            const message = input.value
            input.value = ""


            this.socket.send(
                JSON.stringify({
                    type: "vote",
                    data: message,
                })
            )
        }

        submit_title(event) {
            event.preventDefault()
            const title = document.getElementById("title").value
            const description = document.getElementById("description").value

            this.socket.send(
                JSON.stringify({
                    type: "update_meta",
                    data: {
                        title: title,
                        description: description
                    },
                })
            )
        }

        clear(event) {
            event.preventDefault()

            this.socket.send(
                JSON.stringify({
                    type: "clear_vote",
                })
            )
        }

        kick(event) {
            event.preventDefault()
            const input = document.getElementById("target_user")
            const message = input.value
            input.value = ""


            this.socket.send(
                JSON.stringify({
                    type: "kick",
                    data: message,
                })
            )
        }
    }

    const websocketClass = new myWebsocketHandler()
    websocketClass.setupSocket()

    document.getElementById("button")
        .addEventListener("click", (event) => websocketClass.submit(event))

    document.getElementById("kick_button")
        .addEventListener("click", (event) => websocketClass.kick(event))

    document.getElementById("clear")
        .addEventListener("click", (event) => websocketClass.clear(event))

    const metas = document.getElementsByClassName("meta");

    for (let i = 0 ; i < metas.length ; i ++) {
        console.log(i)
        metas.item(i)
            .addEventListener("input", (event) => websocketClass.submit_title(event))
    }
})()
