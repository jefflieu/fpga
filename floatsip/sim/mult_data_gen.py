#Python Data generator 
import math 
import random
from  float_util import gen_rand_float, is_subnormal, is_inf, FloatingPoint_Specification, hex_rep



coverage_counters = {'nnn' : 0}

def counters(a, b, p, size):
  def get_state(a, size):
    ew, mw = FloatingPoint_Specification[size]
    if a == 0.0: 
      state_a  = 'z' 
    elif is_inf(a, ew): 
      state_a  = 'i'
    elif is_subnormal(a, ew):
      state_a  = 's'
    else : 
      state_a  = 'n'
    return state_a 
  state = get_state(a, size) + get_state(b, size) + get_state(p, size)
  try: 
    coverage_counters[state] = coverage_counters[state] + 1
  except: 
    coverage_counters[state] = 0
  
def generate_mult_test_data(size):
   """
     Lookup the exponent width and mantissa width 
     calculate the BIAS 
     Find the Maximum and Minimum exponent value 
     Generate a Random exp within the range 
     Generate a Random mantissa value within range of (-1.0 and 1.0) 
     a = mant * 2^exp 
     b = mant * 2^exp 
     p = a * b 
     return a, b, p 
   """
   e_width, m_width = FloatingPoint_Specification[size]
   
   a = gen_rand_float(size)
   b = gen_rand_float(size)
   
   p = a * b   
   
   #Check subnormal value and round product to 0 
   #The core is supposed to detect subnormal input
   if is_subnormal(a, e_width) or is_subnormal(b, e_width) or is_subnormal(p, e_width):
     p = 0.0
     
   return a, b, p
  

def main():
    #Seeding 
    random.seed(1.0)
    total_N = 100000
    for size, (e_width, m_width) in FloatingPoint_Specification.items(): 
      print("Test vector for size ", size)
      with open('Mult' + str(size) + 'Data.txt', 'w') as f:
        with open('Mult' + str(size) + 'Real.txt', 'w')  as r:
          for id in range(0, total_N):                
            a, b, p = generate_mult_test_data(size)            
            counters(a, b, p, size) 
            r.write('{:02x} {:<+16e} {} {:<+16e} {} {:<+16e} {}\n'.format(id, a, math.frexp(a), b, math.frexp(b), p, math.frexp(p)))
            f.write('{:02x} {:s} {:s} {:s}\n'.format(id, hex_rep(a, e_width, m_width), hex_rep(b, e_width, m_width), hex_rep(p, e_width, m_width)))
            if ( id % (total_N/100)) == 0: 
               print(id/(total_N/100))
          r.close()
        f.close()
      print("Coverage", coverage_counters)
    

main()