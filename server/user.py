class User:
    def __init__(self, username, socket):
        self.socket = socket
        self.username = username
        
    def notify(self, sender, message):
        builded = f'{sender} {message}\n'
        print('notifying %s' % builded)
        self.socket.sendall(f'{builded}\n'.encode())

class UserRegistry:
    def __init__(self):
        self.users = {}

    def add(self, user):
        if user.username in self.users:
            return False
        self.users[user.username] = user
        return True

    def remove(self, username):
        return self.users.pop(username)

    def get(self, username) -> User:
        return self.users.get(username)

users = UserRegistry()
