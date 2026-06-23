#!/usr/bin/env python3
"""
Multi-Prime RSA Decryption Program
Decrypts RSA messages that use 4 primes instead of 2
"""

import math
import sys
from typing import List, Tuple, Optional


class MultiPrimeRSA:
    """
    Multi-prime RSA implementation for decrypting messages using 4 primes
    """
    
    def __init__(self, primes: List[int], public_exponent: int):
        """
        Initialize multi-prime RSA with 4 primes
        
        Args:
            primes: List of 4 prime numbers [p1, p2, p3, p4]
            public_exponent: The public exponent e
        """
        if len(primes) != 4:
            raise ValueError("Exactly 4 primes are required")
            
        if not all(self.is_prime(p) for p in primes):
            raise ValueError("All values must be prime numbers")
            
        self.primes = primes
        self.e = public_exponent
        self.n = math.prod(primes)  # n = p1 * p2 * p3 * p4
        self.phi = self.compute_phi(primes)
        self.d = self.modular_inverse(public_exponent, self.phi)
        
        if self.d is None:
            raise ValueError("Invalid public exponent - no modular inverse exists")
    
    @staticmethod
    def is_prime(n: int) -> bool:
        """Check if a number is prime"""
        if n < 2:
            return False
        if n in (2, 3):
            return True
        if n % 2 == 0:
            return False
        
        max_divisor = int(math.sqrt(n)) + 1
        for i in range(3, max_divisor, 2):
            if n % i == 0:
                return False
        return True
    
    @staticmethod
    def compute_phi(primes: List[int]) -> int:
        """
        Compute Euler's totient function for product of primes
        φ(n) = (p1-1)(p2-1)(p3-1)(p4-1) for n = p1*p2*p3*p4
        """
        return math.prod([p - 1 for p in primes])
    
    @staticmethod
    def egcd(a: int, b: int) -> Tuple[int, int, int]:
        """Extended Euclidean Algorithm"""
        if a == 0:
            return b, 0, 1
        else:
            g, y, x = MultiPrimeRSA.egcd(b % a, a)
            return g, x - (b // a) * y, y
    
    @classmethod
    def modular_inverse(cls, a: int, m: int) -> Optional[int]:
        """Find modular inverse using extended Euclidean algorithm"""
        g, x, y = cls.egcd(a, m)
        if g != 1:
            return None
        else:
            return x % m
    
    def chinese_remainder_theorem_4(self, remainders: List[int]) -> int:
        """
        Chinese Remainder Theorem for 4 primes
        Solves x ≡ r1 (mod p1), x ≡ r2 (mod p2), x ≡ r3 (mod p3), x ≡ r4 (mod p4)
        """
        if len(remainders) != 4:
            raise ValueError("Need 4 remainders for 4 primes")
        
        p1, p2, p3, p4 = self.primes
        r1, r2, r3, r4 = remainders
        
        # Compute the product of all primes
        N = self.n
        
        # Compute N_i = N / p_i for each prime
        N1 = N // p1
        N2 = N // p2
        N3 = N // p3
        N4 = N // p4
        
        # Compute modular inverses
        M1 = self.modular_inverse(N1, p1)
        M2 = self.modular_inverse(N2, p2)
        M3 = self.modular_inverse(N3, p3)
        M4 = self.modular_inverse(N4, p4)
        
        if any(m is None for m in [M1, M2, M3, M4]):
            raise ValueError("Failed to compute modular inverses")
        
        # Apply CRT formula
        x = (r1 * N1 * M1 + r2 * N2 * M2 + r3 * N3 * M3 + r4 * N4 * M4) % N
        return x
    
    def decrypt(self, ciphertext: int) -> int:
        """
        Decrypt ciphertext using multi-prime RSA with CRT optimization
        
        Args:
            ciphertext: The encrypted message as integer
            
        Returns:
            The decrypted message as integer
        """
        # Compute remainders: c^d mod p_i for each prime
        remainders = []
        for prime in self.primes:
            # Use pow with three arguments for efficient modular exponentiation
            remainder = pow(ciphertext, self.d, prime)
            remainders.append(remainder)
        
        # Use CRT to combine remainders
        plaintext = self.chinese_remainder_theorem_4(remainders)
        return plaintext
    
    def decrypt_slow(self, ciphertext: int) -> int:
        """
        Decrypt without CRT optimization (slower but simpler)
        """
        return pow(ciphertext, self.d, self.n)


def bytes_to_int(data: bytes) -> int:
    """Convert bytes to integer"""
    return int.from_bytes(data, byteorder='big')


def int_to_bytes(number: int) -> bytes:
    """Convert integer to bytes"""
    if number == 0:
        return b'\x00'
    
    length = (number.bit_length() + 7) // 8
    return number.to_bytes(length, byteorder='big')


def main():
    """
    Example usage of multi-prime RSA decryption
    """
    print("Multi-Prime RSA Decryption (4 Primes)")
    print("=" * 40)
    
    # Example with 4 small primes for demonstration
    # In practice, these would be much larger (1024+ bits each)
    primes = [61, 53, 47, 43]  # 4 small primes
    e = 65537  # Common public exponent
    
    try:
        # Initialize RSA
        rsa = MultiPrimeRSA(primes, e)
        
        print(f"Primes: {primes}")
        print(f"Public exponent (e): {e}")
        print(f"Modulus (n): {rsa.n}")
        print(f"Private exponent (d): {rsa.d}")
        print()
        
        # Example message (use smaller message for demo with small primes)
        message = "Hi!"
        message_bytes = message.encode('utf-8')
        message_int = bytes_to_int(message_bytes)
        
        print(f"Original message: {message}")
        print(f"Message as integer: {message_int}")
        print()
        
        # Make sure message is smaller than modulus
        if message_int >= rsa.n:
            print("Message too large for modulus, using smaller message")
            message = "A"
            message_bytes = message.encode('utf-8')
            message_int = bytes_to_int(message_bytes)
            print(f"New message: {message}")
            print(f"New message as integer: {message_int}")
        
        # Encrypt (for demonstration - in practice you'd receive ciphertext)
        ciphertext = pow(message_int, e, rsa.n)
        print(f"Ciphertext: {ciphertext}")
        print()
        
        # Decrypt using CRT (fast method)
        decrypted_int = rsa.decrypt(ciphertext)
        decrypted_bytes = int_to_bytes(decrypted_int)
        decrypted_message = decrypted_bytes.decode('utf-8')
        
        print(f"Decrypted (CRT): {decrypted_message}")
        print(f"Match original: {message == decrypted_message}")
        print()
        
        # Verify with slow method
        decrypted_slow = rsa.decrypt_slow(ciphertext)
        decrypted_slow_bytes = int_to_bytes(decrypted_slow)
        decrypted_slow_message = decrypted_slow_bytes.decode('utf-8')
        
        print(f"Decrypted (slow): {decrypted_slow_message}")
        print(f"Methods match: {decrypted_int == decrypted_slow}")
        
    except Exception as e:
        print(f"Error: {e}")
        return 1
    
    return 0


def interactive_mode():
    """
    Interactive mode for decrypting custom messages
    """
    print("\nInteractive Multi-Prime RSA Decryption")
    print("=" * 45)
    
    try:
        # Get primes from user
        primes = []
        for i in range(4):
            while True:
                try:
                    prime = int(input(f"Enter prime #{i+1}: "))
                    if MultiPrimeRSA.is_prime(prime):
                        primes.append(prime)
                        break
                    else:
                        print("Not a prime number. Please try again.")
                except ValueError:
                    print("Invalid input. Please enter an integer.")
        
        # Get public exponent
        while True:
            try:
                e = int(input("Enter public exponent (e): "))
                break
            except ValueError:
                print("Invalid input. Please enter an integer.")
        
        # Initialize RSA
        rsa = MultiPrimeRSA(primes, e)
        print(f"\nModulus (n): {rsa.n}")
        print(f"Private exponent (d): {rsa.d}")
        
        # Get ciphertext
        while True:
            try:
                ciphertext = int(input("\nEnter ciphertext to decrypt: "))
                break
            except ValueError:
                print("Invalid input. Please enter an integer.")
        
        # Decrypt
        decrypted_int = rsa.decrypt(ciphertext)
        decrypted_bytes = int_to_bytes(decrypted_int)
        
        try:
            decrypted_message = decrypted_bytes.decode('utf-8')
            print(f"\nDecrypted message: {decrypted_message}")
        except UnicodeDecodeError:
            print(f"\nDecrypted bytes (hex): {decrypted_bytes.hex()}")
            print(f"Decrypted integer: {decrypted_int}")
        
    except Exception as e:
        print(f"Error: {e}")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--interactive":
        interactive_mode()
    else:
        exit(main())
