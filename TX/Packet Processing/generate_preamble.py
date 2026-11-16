import numpy as np
import math

# =====================================================================
# 1. FIXED-POINT PARAMETERS (Change here (Q2.14))
# =====================================================================
INTEGER_BITS = 2        # 1 Sign bit + 1 Integer bit
FRACTIONAL_BITS = 14    # Use 14 for (Q2.14 / 16-bit) OR 10 for (Q1.10 / 12-bit)
OUTPUT_FILE = "preamble_rom_data.mem"


def generate_ieee_80211a_preamble():        #File used later by the ROM
    """Generates the mathematically exact 320-sample baseband preamble."""
    
    # 1. STS in Frequency Domain
    sts_k = np.zeros(64, dtype=complex)
    factor = math.sqrt(13/6)
    
    # STS Subcarriers allocation (-24 to +24 with step of 4)
    sts_indices = [-24, -20, -16, -12, -8, -4, 4, 8, 12, 16, 20, 24]
    sts_values = [1+1j, -1-1j, 1+1j, -1-1j, -1-1j, 1+1j, -1-1j, -1-1j, 1+1j, 1+1j, 1+1j, 1+1j]
    
    for idx, val in zip(sts_indices, sts_values):
        sts_k[idx] = val * factor

    # 2. LTS in Frequency Domain
    lts_k = np.zeros(64, dtype=complex)
    lts_seq = [1, 1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 1, 1, -1, -1, 1, 1, -1, 1, -1, 1, 1, 1, 1, 0,
               1, -1, -1, 1, 1, -1, 1, -1, 1, -1, -1, -1, -1, -1, 1, 1, -1, -1, 1, -1, 1, -1, 1, 1, 1, 1]
    
    # Map LTS to subcarriers -26 to +26
    lts_idx = 0
    for i in range(-26, 27):
        lts_k[i] = lts_seq[lts_idx]
        lts_idx += 1

    # 3. Convert to Time Domain using IFFT (Note: IEEE standard normalizes IFFT by multiplying by sqrt(N) = 8)
    sts_t = np.fft.ifft(sts_k) * 8
    lts_t = np.fft.ifft(lts_k) * 8

    # 4. Construct the 320-sample Time Domain Preamble
    
    # STS: 10 repetitions of the first 16 samples (= 160 samples)
    sts_160 = np.tile(sts_t[0:16], 10)
    
    # LTS: Guard Interval 2 (last 32 samples) + 2 repetitions of full 64 samples (= 160 samples)
    gi2 = lts_t[-32:]
    lts_160 = np.concatenate((gi2, lts_t, lts_t))

    # Total Preamble = 320 samples
    return np.concatenate((sts_160, lts_160))

# =====================================================================
# 2. GENERATE MATHEMATICAL DATA
# =====================================================================
print("Generating IEEE 802.11a Preamble math...")
preamble_complex = generate_ieee_80211a_preamble()

# =====================================================================
# 3. EXPORT TO MEMORY FILE (Fixed-Point Conversion)
# =====================================================================
total_bits = INTEGER_BITS + FRACTIONAL_BITS
scaling_factor = 2 ** FRACTIONAL_BITS
hex_chars = math.ceil(total_bits / 4.0)
bitmask = (1 << total_bits) - 1 

print(f"Converting to Fixed-Point (Q{INTEGER_BITS-1}.{FRACTIONAL_BITS})...")

with open(OUTPUT_FILE, "w") as f:
    for val in preamble_complex:
        
        # Multiply by scaling factor and round to integer
        i_scaled = int(np.round(val.real * scaling_factor))
        q_scaled = int(np.round(val.imag * scaling_factor))
        
        # Convert to Two's Complement
        i_hex_val = i_scaled & bitmask
        q_hex_val = q_scaled & bitmask
        
        # Format and Write to file
        format_str = f"{{i_val:0{hex_chars}X}}{{q_val:0{hex_chars}X}}\n"
        f.write(format_str.format(i_val=i_hex_val, q_val=q_hex_val))

print(f"Success! Saved to '{OUTPUT_FILE}'")
print(f"Format Info: {total_bits}-bit bus width | Scaling Factor: {scaling_factor}")