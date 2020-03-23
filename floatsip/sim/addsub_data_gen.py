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
  
def generate_addsub_test_data(size):
    
    e_width, m_width = FloatingPoint_Specification[size]
    
    a = gen_rand_float(size)
    b = gen_rand_float(size)
    
    op = random.randint(0,1)
    
    ##The AddSub core doesn't support subnormal inputs and will round the inputs to zero 
    if op : 
      s = a - b   
      if is_subnormal(a, e_width) and (not is_subnormal(b, e_width)):    
        s = - b
      elif (not is_subnormal(a, e_width)) and is_subnormal(b, e_width):    
        s = a  
      elif is_subnormal(a, e_width) and is_subnormal(b, e_width):    
        s = 0.0
      elif is_subnormal(s, e_width): 
        s = 0.0
    else : 
      s = a + b
      if is_subnormal(a, e_width) and (not is_subnormal(b, e_width)):    
        s = b
      elif (not is_subnormal(a, e_width)) and is_subnormal(b, e_width):    
        s = a  
      elif is_subnormal(a, e_width) and is_subnormal(b, e_width):    
        s = 0.0
      elif is_subnormal(s, e_width): 
        s = 0.0
    
    
    
    return op, a, b, s
  

def main():
    #Seeding 
    random.seed(1.0)
    total_N = 100000
    for size, (e_width, m_width) in FloatingPoint_Specification.items(): 
      print("Test vector for size ", size)
      with open('AddSub' + str(size) + 'Data.txt', 'w') as f:
        with open('AddSub' + str(size) + 'Real.txt', 'w')  as r:
          for id in range(0, total_N):                
            op, a, b, s = generate_addsub_test_data(size)            
            counters(a, b, s, size) 
            r.write('{:08x} {:<+16e} {:30s} {:<+16e} {:30s} {:<+16e} {:30s}\n'.format(id|(op<<31), a, math.frexp(a), b, math.frexp(b), s, math.frexp(s)))
            f.write('{:08x} {:s} {:s} {:s}\n'.format(id|(op<<31), hex_rep(a, e_width, m_width), hex_rep(b, e_width, m_width), hex_rep(s, e_width, m_width)))
            if ( id % (total_N/100)) == 0: 
               print(id/(total_N/100))
          r.close()
        f.close()
      print("Coverage", coverage_counters)
    

main()