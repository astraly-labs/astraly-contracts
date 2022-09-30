import random
from collections import namedtuple


UserParticipation = namedtuple("UserParticipation", ["address", "score"])

user_array = list(
    [
        UserParticipation(1, 5),
        UserParticipation(2, 5),
        UserParticipation(3, 5),
        UserParticipation(5, 5),
        UserParticipation(6, 5),
        UserParticipation(7, 5),
        UserParticipation(8, 5),
        UserParticipation(9, 5),
        UserParticipation(10, 5),
        UserParticipation(11, 5),
        UserParticipation(12, 50),
    ]
)

batch_size = 5


for round in range(10):
    winners = list()
    for i in range(batch_size):
        res = list()
        for user in user_array:
            rnd = random.getrandbits(64)
            value = rnd * user.score
            res.append((user.address, value))
        max_weight = max(res, key=lambda x: x[1])
        winners.append(max_weight[0])

    print(winners)
