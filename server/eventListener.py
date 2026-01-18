import eventQueue
from eventQueue import evQueue

import user
from user import users

def handle_message(message):
    sender = message[0]
    event = message[1]

    if event == 'connection':
        res = users.add(sender)
        if not res:
            return 'User already exists'
        return 'User connected as %s' % message[1] 
    if event == 'disconnection':
        users.remove(sender.username)
        return
    if event == 'message':
        receiver = users.get(message[2])
        if receiver.notify(sender.username, message[3]):
            return 'Message broken'
        return 'Message sent'

    return message

def handle_messages():
    while True:
        if evQueue.is_empty():
            continue
        message = evQueue.get()
        print(handle_message(message))
