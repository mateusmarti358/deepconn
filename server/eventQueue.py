from queue import Queue

class EventQueue:
    def __init__(self):
        self.queue = Queue()

    def put(self, event):
        self.queue.put(event)
    
    def get(self):
        return self.queue.get()

    def is_empty(self):
        return self.queue.empty()

evQueue = EventQueue()
