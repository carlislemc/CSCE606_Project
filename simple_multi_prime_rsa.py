#!/usr/bin/env python3
import math

def crt_4(primes, remainders):
    N = math.prod(primes)
    result = 0
    for i, (p, r) in enumerate(zip(primes, remainders)):
        Ni = N // p
        # Find modular inverse of Ni mod p
        Mi = pow(Ni, -1, p)
        result += r * Ni * Mi
    return result % N

def egcd(a, b):
    if a == 0:
        return b, 0, 1
    g, y, x = egcd(b % a, a)
    return g, x - (b // a) * y, y

def modinv(a, m):
    g, x, y = egcd(a, m)
    return x % m if g == 1 else None

def decrypt_multi_prime_rsa(primes, ciphertext, e=65537):
    n = math.prod(primes)
    phi = math.prod([p - 1 for p in primes])
    d = modinv(e, phi)
    
    # Compute remainders
    remainders = [pow(ciphertext, d, p) for p in primes]
    
    # Use CRT to combine
    return crt_4(primes, remainders)

if __name__ == "__main__":
    # Example usage
    primes = [61, 53, 47, 43]  # Your 4 primes
    e = 65537
    ciphertext = 4292141  # Your ciphertext
    
    plaintext = decrypt_multi_prime_rsa(primes, ciphertext, e)
    print(f"Decrypted: {plaintext}")
    
    # Convert to text if needed
    try:
        text = plaintext.to_bytes((plaintext.bit_length() + 7) // 8, 'big').decode('utf-8')
        print(f"As text: {text}")
    except:
        print(f"As hex: {hex(plaintext)}")
