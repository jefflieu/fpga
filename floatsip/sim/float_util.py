
import math 
import random

FloatingPoint_Specification = {
     32 : ( 8, 23)  ,
     64 : (11, 52)  ,
     16 : ( 5, 10)  
}

def is_inf(dbl, exp_width):
  bias  = (1<<(exp_width - 1)) - 1
  max_e = (1<<exp_width) - 1 - 1 - bias
  if exp_width == 11:
    return math.isinf(dbl)
  else: 
    return (dbl >= math.ldexp(1.0, max_e + 1) or dbl < math.ldexp(-1.0, max_e + 1))

def is_subnormal(dbl, exp_width):
  bias = (1<<(exp_width - 1)) - 1
  min_e = 1 - bias 
  return ((dbl < math.ldexp(1.0, min_e) and dbl > math.ldexp(-1.0, min_e)) and dbl != 0.0)


def gen_rand_float(size):
   e_width, m_width = FloatingPoint_Specification[size]
   m = random.randint(0, 2**(m_width + 1) - 1)
   mant = m/2.0**m_width
   bias = (1<<(e_width - 1)) - 1
   max_e = ((1 << e_width) - 1) - 1 - bias   
   min_e = (1 - bias)
   exp  = random.randint(min_e, max_e)   
   return math.ldexp(mant, exp)

def round_to_nearest_even(dbl): 
    upper = math.ceil(dbl)
    lower = math.floor(dbl)
    error = dbl - lower 
    ret = 0
    if error == 0.5: 
      if (upper % 2)==0:
        ret = upper
      else: 
        ret =lower 
    elif error < 0.5: 
      ret = lower 
    else: 
      ret = upper     
    return int(ret)

def hex_rep(dbl, exp_width = 8, mant_width = 23):
  """ 
    This function returns hex representation of dbl value with a custom exp_width and mant_width 
    First find out the BIAS and the representation of the dbl 
    dlb = m * 2^e ( m is [-1.0, 1.0])
    Then we handle infinity, handle subnormal number and special case for zero 
  """
  
  bias = (1<<(exp_width - 1)) - 1
  m, e = math.frexp(dbl)
  
  try:
    #Infinity number 
    if is_inf(dbl, exp_width):
      mant = 0 
      exp  = (1<<exp_width) - 1
    
    #subnormal numbers
    elif is_subnormal(dbl, exp_width):       
      """
        subnormal number a = s * 0.m * 2^min_e (min_e = 1 - bias)
        the frexp() returns normalized m and e with 0.5 <= m <= 1.0 and e can be smaller than 1 - bias         
        to represent a = m x 2^e in subnormal format = 0.frac x 2^min_e 
        we have to unnormalize the mantissa 
           frac = m / (2^(min_e - e))
        then multiply by number of bits of mantissa = 2^mant_width
        --> frac = m * 2^(mant_width - (min_e - e)) 
      """
      exp  = 0  
      k = (1-bias) - e
      if m < 0: 
        m = 0 - m
      if mant_width >= k:
        mant =  int(m *(1<<(mant_width  - k)))
      else:
        mant =  0
    else:       
      #Special case of mantissa = 0
      if m == 0:
        exp  = 0
        mant = 0
      else:
        if m < 0: 
          m = 0 - m
        mant =  round_to_nearest_even((m * 2 - 1.0)*(1<<mant_width))
        exp  =  (e - 1) + bias     
  except: 
    print("Unknown exception", dbl, m, e, exp_width, mant_width, is_inf(dbl, exp_width), is_subnormal(dbl, exp_width), k)
    pass 
  
  #Set up sign bit first   
  if dbl < 0: 
    hex_rep = 1 
  else: 
    hex_rep = 0
  
  #Shift in exponential and mantissa 
  hex_rep = (hex_rep << exp_width) + exp 
  hex_rep = (hex_rep << mant_width) + mant     
  fmtspec = '{:0' + str((exp_width + mant_width + 1 + 3)/4) + 'x}'
  return fmtspec.format(hex_rep)
