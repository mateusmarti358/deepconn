import user as userlib
from eventQueue import evQueue

def parse_req(userId, req):
    if req[0] == 'message':
        evQueue.put(('message', req[1], req[2]))

def handle_client(client_socket):
    client_name = client_socket.recv(1024).decode().strip()
    user = userlib.User(client_name, client_socket)

    evQueue.put(('connection', user))

    while True:
        message = client_socket.recv(1024).decode().strip()

        if message == 'exit':
            break

        evQueue.put(('message', user, message))
    
    evQueue.put(('disconnection', user))
    client_socket.close()
