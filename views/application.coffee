$(document).ready ->
  ws = new WebSocket("ws://37.187.40.7:8080")
  ws.onopen = ->
    console.log "connected..."
    name = prompt("Podaj imie:", "Robert")
    ws.send name
    $.getJSON "http://torianinmobile.pl/api/map.json", (data) ->
      console.log data
    window.canvas = new gameCanvas
    window.canvas.draw()
  ws.onmessage = (evt) ->
    console.log evt.data
  ws.onclose = ->
    console.log "socket closed"

class gameCanvas
  constructor: ->
    @c = document.getElementById("game")
    @ctx = @c.getContext("2d")
    @ctx.font = "15px Arial"
    @url = "./img/angel.png"
    @url_rotate = "./img/angel_rotate.png"
    @backgroundurl = "./img/background.png"
  draw: ->
    console.log "dziala"
    @img = new Image()
    @img.src = @url
    @background = new Image()
    @background.src = @backgroundurl
    @ctx.drawImage @background, 0, 0
    @ctx.drawImage @background, 0, 0

