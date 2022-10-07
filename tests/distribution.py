from random import randint
from collections import namedtuple, Counter


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

for x in range(50000):
    user_array.append(UserParticipation(randint(99999, 9999999999999), randint(1, 100)))
print("AVG SCORE : ", sum([u.score for u in user_array]) / len(user_array))

k = 10000
R = []
W = []
for user in user_array:
    R.append(user)
    if len(W) < k:
        W.append(user)
    else:
        j = randint(0, k - 1)
        i = randint(0, len(R) - 1)
        if R[i].score <= user.score:
            if W[j].score <= user.score:
                W[j] = user

        if user.score <= R[i].score:
            W[j] = R[i]

# print("Registrants", R)
# print("Winners", W)
print("AVG WINNER SCORE : ", sum([u.score for u in W]) / len(W))
print("WINNERS UNIQUE VALUES : ", len(set(W)))
print(Counter(W).most_common(20))
