import bcrypt

password = "YOUR_PASS".encode("utf-8")
hashed = bcrypt.hashpw(password, bcrypt.gensalt(rounds=10))

# Reemplazar $2b$ por $2y$ (solo si realmente lo necesitás)
hashed_2y = hashed.replace(b"$2b$", b"$2y$")

print(hashed_2y.decode())
