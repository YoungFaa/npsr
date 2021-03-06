##' @keywords internal
##' @param l |Z|
##' @param m |X|
##' @param n |Y|
##' @param Rxy Matrix of response function indicators
##' @param y_zx_dependent If set to true P will be calculated assuming Y is dependent on z and x, otherwise will assume y is only dependent on x.
##' @title Create_P
##' @description Creates a l\*m\*n x (m^l)\*(n^m) dimensional matrix if y_zx_dependent = FAlSE, creates l\*m\*n x (m^l)\*((n^m)+1) dimension matrix otherwise.
Create_P = function(l,m,n, Rxy, y_zx_depenendent = FALSE){
  # Vector of all possible Observations (Q and ZXY have to relate to the same indices)
  ZXY = expand.grid((1:l), (1:m), (1:n)) # l*m*n x 3 matrix

  # P is the probability matrix for the realization of an observation given
  # a pair of response function for x and y (rows are observation, columns are repsponse functions)
  P = outer(1:nrow(ZXY), 1:nrow(Rxy), function(r,c){
    #r and c are (l*m*n)*(n^m)*(n^l) dimensional vectors
    # extend ZXY for all possible response functions
    zxy = ZXY[r,]
    #extend Rxy for all possible observations
    rows = rep(1:nrow(Rxy), each = nrow(ZXY))
    rxy = Rxy[rows,]

    #determine x based on observed z for each Rxy
    x_d = unlist(rxy[cbind(1:nrow(zxy),zxy[,1])])
    #determine y based on determined x for each Rxy


    if(y_zx_depenendent){
      y_d = rxy[cbind(1:nrow(zxy),l + x_d*zxy[,1])]
      #y_d = rxy[cbind(1:nrow(zxy),(l + (x_d*(l-1)) + zxy[,1]))]
    }else{
      y_d = rxy[cbind(1:nrow(zxy),l + x_d)]
    }

    is_x = zxy[,2]==x_d
    is_y = zxy[,3]==y_d

    is_xy = is_x & is_y

    return (is_xy*1)
  })
}

##' @keywords internal
##' @title estimate_integral
##' @param N Number of Repetitions
##' @param S Number of Starting Points
##' @param d number of dimension of point
##' @param llf log likelihood function
##' @description Estimates multidimensional integral using nested sampling.
estimate_integral = function(N,S,d,llf,sample_theta){
  lpf = function(t) 1 # Prior is uniform, thus constant

  sig = d^(-0.5)/10 # according to Skilling (2009), we use factor 10 to be far less than C^-0.5
  H = ceiling(-d * log(sig) * sqrt(d))
  S_calculated = 100 + d
  N_calculated = d*100 #H * S_calculated;
  # Create Data Frame 'cs' of starting point to work with RNested
  points = starting_points(S_calculated,d, sample_theta)
  starting_ll = apply(t(points), 2, llf)
  starting_lp = rep(0.0, S_calculated);

  cs = data.frame(p=I(points), ll=starting_ll, lpr=starting_lp)
  sampler = make_sampler(d, 1000,sample_theta);
  estimate = nested.sample(cs = cs,llf = llf,lpf = lpf, N = N_calculated, psampler = sampler)
  # Calculate the evidence according to Skilling (2005)
  result_ll = ifelse(estimate$cout$ll==-Inf,0, estimate$cout$ll)
  start_ll = ifelse(cs$ll == -Inf, 0, cs$ll)
  evidence = sum(estimate$cout$w * result_ll) #increment Z by Li*wi
  evidence = evidence+ (exp(-N/S_calculated) * sum(start_ll)/N)
  return (evidence)
}
##' @keywords internal
##' @description Creates a set of N starting Points for theta Z
##' @title starting_points
##' @param N number of samples
##' @param d number of dimensions
starting_points = function(N, d, sample_theta){
  sp = rep(d, N)
  sp = apply(t(sp), 2, sample_theta)
  return (sp)
}
##' @keywords internal
##' @description Creates a function which proposes new random theta.
##' @title make_proposer
##' @param d number of dimensions of theta
##' @param N function to sample new theta
make_proposer = function(d, sample_theta){
  current_prev = NULL
  current_now = NULL
  proposer = function(current){
    if(!is.null(current_now) && current_now == current){
      #the last proposed point did not have a higher likelihood
      #give up walking, and restart with random sample
      return (sample_theta(d))
    }else{
      #the last proposed point did have a higher likelihood
      current_prev = current_now
      current_now = current
      if(is.null(current_prev)){
        # first time sampling for this starting point
        # let's walk into a random direction
        step_size = 0.1 * 1/d #how big the next step in the space should be
        step_sample = unlist(sample_theta(d)); #directions for next step
        step_sample = step_sample / step_size # scaled step according to step_size
        new_sample = unlist(current) + step_sample
        new_sample = new_sample/sum(new_sample) # normalized to sum 1
        return (list(new_sample))
      }
      #keep walking into same direction as previously
      direction = current_now - current_prev;
      new_sample = current_now + direction;
      # in case we walked out of the valid sample space
      new_sample[new_sample<0] = 0
      new_sample = new_sample/sum(new_sample)
      return (list(new_sample))
    }

    step_size = 0.1 * 1/d #how big the next step in the space should be
    step_sample = unlist(sample_theta(d)); #directions for next step
    step_sample = step_sample / step_size # scaled step according to step_size
    new_sample = unlist(current) + step_sample
    new_sample = new_sample/sum(new_sample) # normalized to sum 1
    return (list(new_sample))
  }
  return (proposer)
}
##' @keywords internal
##' @description Creates a sampler function which finds a new point with a higher log likelihood.
##' @title make_sampler
##' @param d Dimensions of point
##' @param s Number of mcmc walker steps
##' @return Sampler function which tries to find a point with a higher likelihood than the given point
make_sampler = function(d,s,sample_theta){
  proposer = make_proposer(d, sample_theta)
  sampler = function(worst, llf, lpf, cs){
    found = CPChain(worst, proposer, s, llf, lpf,cs)
    return (found)
  }
}
##' @keywords internal
##' @description Calculate the product of theta sums to the power of Qi over Q.
##' @title XY_product
##' @param theta_xy probability vector for response variables
##' @param P Probability matrix
##' @param Q Histogram of unique observations
XY_product = function(theta_xy, P, Q){
  sums = P %*% theta_xy
  powered_sums = sums ^ Q
  product = prod(powered_sums)
  return (product)
}
##' @keywords internal
##' @description Calculate the product of theta to power of Qi over Q.
##' @title Z_product
##' @param theta_z probability vector
##' @param Q Histogram of unique observations
Z_product = function(theta_z, Q){
  powered = unlist(theta_z)^Q
  product = prod(powered)
  return (product)
}

sample_theta = function(d){
  t = runif(d)
  t = t/sum(t) #make sure that all probablities add up one
  return (list(t))
}
