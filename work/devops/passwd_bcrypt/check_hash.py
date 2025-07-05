import bcrypt

# Tu contraseña ingresada por el usuario
password = "YOUR_PASS".encode("utf-8")

# Hash almacenado en la base de datos
hashed = b"THE_HASH_2Y_YOU_HAVE"

# Validación
if bcrypt.checkpw(password, hashed):
    print("Contraseña válida ✅")
else:
    print("Contraseña incorrecta ❌")

