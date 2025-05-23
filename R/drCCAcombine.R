#' Title
#'
#' @param datasets : list of data matrices
#' @param reg : regularization value
#' @param nfold : number of cross validations
#' @param nrand : number of iterations for random matrix generation
#'
#' @return proj : projection
#' @return n : data with recommended features(counts)
#' @export
#'
#' @examples
#' library(lcca)
drCCAcombine <-
function(datasets,reg=0,nfold=3,nrand=50)
{

  mat <- datasets #list of data matrices

  reg <- reg #regularization value


  n <- nfold # number of cross validations


  iter <- nrand # number of iterations for random matrix generation

  if(reg < 0){reg <- 0}

  if(nfold <= 0){n <- 3} #use default value

  if(nrand <= 0){iter <- 50} #use default value

  m <- length(mat)  #number of  data matrices


##########################################################
#########################################################



## internal subroutine 1 , part
part <- function(data, nfold)
{
    mat <- as.matrix(data) # read the data file

    r <- nrow(mat)

    n <- nfold #the number for partition

   parts <- array(list(),n) #divide the data in n parts

   for(i in 1:n)
   {
    parts[[i]] <- as.matrix(mat[((((i-1)*r)%/%n) + 1): ((i*r)%/%n), ])

     #print(dim(parts[[i]]))
   }

   test <- array(list(),n)
   train <- array(list(),n)

   for(i in 1:n)
   {
      test[[i]] <- parts[[i]]

      for(j in 1:n)
      {
      if(j != i)
      train[[i]] <- rbind(train[[i]],parts[[j]])
      }
   }

     #partition <- new.env()
     #partition$train <- train
     #partition$test <- test
     #as.list(partition)

     partition <- list(test = test, train = train)
     return(partition);
}


###subroutine 2
## supporting script for subroutine 2

 drop <- function(mat,parameter)
{
      mat <- as.matrix(mat)

      p <- parameter


      fac <- svd(mat)

      len <- length(fac$d)
      ord <- order(fac$d) #sort in increasing order,ie smallest eig val first

      ord_eig <- fac$d[ord] #order eig vals in increasing order

     # cumulative percentage of Frobenius norm

     portion <- cumsum(ord_eig^2)/sum(ord_eig^2)

     ind <- which(portion < p) #ind r those who contribute less than p%

     #print('original number of dimensions')
     #print(length(portion))
     #print('number of dimensions dropped')
     #print(length(ind))
     #print(ind)

      #drop eig vecs corrsponding to small eig vals dropped
       num <- len -length(ind)

      fac$v <- as.matrix(fac$v[,1:num])

      fac$u <- as.matrix(fac$u[,1:num])

      mat_res <- (fac$v %*% sqrt(diag(1/fac$d[1:num],nrow = length(fac$d[1:num])))%*% t(fac$u))

      return(mat_res);

}


##Subroutine 2.
# To calculate gCCA for training sets, Regularized or unregularized gCCA
# input 1. concatenated training matrices
# input 2. Number of features in each training sets
# input 3. Regularization parameter, 0 will indicate unregularized gCCA

   reg_cca <- function(list,reg= 0)
{

   mat <- list # list of mats

   reg <- reg

   m <- length(mat)

   covm <- array(list(),m) #covariance matrices

   for(i in 1:m)
   {

    mat[[i]] <- apply(mat[[i]],2,function(x){x - mean(x)})

    covm[[i]] <- cov(mat[[i]])
   }

   #whitening of data

    white <- array(list(),m) #whitening matrices

    whiten_mat <- array(list(), m) #whitened data

    if (reg > 0)
       {
            for (i in 1:m)
                {
                whiten_mat[[i]] <- mat[[i]] %*% drop(covm[[i]],reg)
                white[[i]] <- drop(covm[[i]],reg)
                }
        }else
           {
              for (i in 1:m)
               {
                whiten_mat[[i]] <- mat[[i]] %*% SqrtInvMat(covm[[i]])
                white[[i]] <- SqrtInvMat(covm[[i]])
               }
           }

        tr_a <- do.call(cbind,whiten_mat)
        tr_z <- cov(tr_a)
        eig <- svd(tr_z)
        x <- list(eigval = eig$d, eigvecs = eig$v, white = white)
        return(x)



}


### subroutine 6

separate <- function(data,fea)
{

  data <- data #concatenated data

  fea <- fea #vector of column numbers

  m <- length(fea)

  mat <- array(list(), m)

       j <- 0
       for (i in 1:m)
           {
            mat[[i]] <- data[, (j + 1):(j + fea[i]), drop = FALSE]
            j <- j + fea[i]
           }

    return(mat)

}


##suboutine 3.
#SUBROUTINE FOR TEST DATA

eigtest <- function(test,train,fea,reg=0)
{

   test <- test #concatenated test set

   train <- train #concatenated train set

    fea <- fea

    reg <- reg

   ##gcca of training data

     #create list, subroutine 6
     tr_mat <- separate(train,fea)

     cca <- reg_cca(tr_mat,reg) #subroutine 5.

     vecs <- cca$eigvecs #tranining eig vecs

     white <- cca$white #whitening matrices

     #print('check')
     #print(dim(white[[1]]))

    ## test matrices

      mat <- separate(test,fea) #list of test data

    #whitening of data with training whitening matrices

    k <- length(fea)

    whiten_mat <- array(list(),k)  # array of matrices after whitening

    for(i in 1:k)
     {

       mat[[i]] <- apply(mat[[i]],2,function(x){x - mean(x)})

       whiten_mat[[i]] <- mat[[i]] %*% white[[i]]
     }

     ##concatenating the matrices

     con <- do.call(cbind,whiten_mat)

     #full covariance matrix
      z  <- cov(con)

      # it is now zy = lambda y
      # we use traning eig vecs in place of y & calculate eig vals for test

      v <- ncol(vecs)

    lambda <- matrix(,v) # create a matrix for lambdas

      for(i in 1:v)
      {
       lambda[i,] <- (t(vecs[,i])) %*% z %*% (vecs[,i])

      }

    return(lambda);

}





##SUBROUTINE 4.
#To calculate random matrices from training data and their eigen values
#Inputs :concatenated training matrix; feature vector; number of iterations
random_eig <- function(train,fea,iter,row)
{
     mat <- train #concatenated training matrices

     iter <- iter #number of iterations

     fea <- fea #  feature vector column

     row <- row #number of samples in original data

     #print(fea)

     dims <- sum(fea) #total number of features

     k <- length(fea) # number of matrices

      #first separate all matrices


      mats <- separate(mat,fea)

       #now generate random matrices

      ################################################################

      #create random matrix from multivariate normal distribution
      # using training data

      library("MASS")

      #################################################################


   #will create n samples of random matrices from training data
   #will calculate eigen values for each sample
   #store eigen values in a matrix, one row per sample

    mat_eigen <- matrix( ,iter,dims) # eig vals for each sample as each row
                                     # of this matrix


    for(n in 1:iter)  # n is running for number of samples

    {
    ran1 <- array(list(),k) #first set of random matrices

       for(i in 1:k)
          {
           ran1[[i]] <- random(mats[[i]],row)

          # print(dim(ran1[[i]]))
          }

   #eig <- reg_cca(ran1)
   #mat_eigen[n,] <- eig$eigval #eig vals getting stored in a matrix

   #cross validation on each random set

           ranfull <- do.call(cbind,ran1)

   #create training and test

          r_train <- ranfull[1:nrow(mat),]

          r_test <- ranfull[(nrow(mat)+1):row,]


    # test eigen value

           mat_eigen[n,] <- eigtest(r_test,r_train,fea,0)

    }

  mat_eigen; #returning eig vals in a matrix

  return(mat_eigen)

}


#subroutine

# create random matrices

random <- function(mat,row)

  {
       mat <- mat

       row <- row #samples to generate

       v <- apply(mat,2,var)

       sigma <- diag(v,ncol = length(v))

        mu <- c(rep(0,length(v)))
        rand <- mvrnorm(row,mu,sigma)

        return(rand);

  }

## SUBROUTINE 5.
# will compare each test eigvals with whole random eigvals
# return the number of test eigen values which are greater than all random
#eigen values

#input: each row of test eigvals and corresponding matrix of random eigvals

 comp <- function(test_eigen_value,ran_eigen_value)
  {

     test_eig <- test_eigen_value  #one row

     ran_eig <- ran_eigen_value    #random rig val matrix

     p <- length(test_eig)

     r <- nrow(ran_eig)

      #print(dim(ran_eig))

      count <- 0
      for(i in 1:p)
      {
        if( (score <- length(which(test_eig[i] >= ran_eig))) >  (98*r*p)/100)

          {count <- count +1}else{break}
       }
      return(count);
   }

#SUBROUTINES END HERE#
################################################################
################################################################


  ##PRINT THE NAME OF FILES IN THE INPUT FILE
   print("Number of input matrices")
   print(m)

   fea <- c(rep(0,m)) # Number of features in each matrix

  # make the data matrices zero mean

    for(i in 1:m)
    {

     mat[[i]] <- apply(mat[[i]],2,function(x){x - mean(x)})


     fea[i] <- ncol(mat[[i]])
    }

  ## concatenate all matrices columnwise

     a <- do.call(cbind,mat)    #use internal subroutine


  # CREATING TEST AND TRAINING SETS for concatenated data for NFOLD Cross
  #Validation

     res <- part(a,n)  #calling subroutine 1.

     test <- res$test  # all test sets

     train <- res$train # all training sets

     print("Number of test and training matrices created")

     print( len <-length(test))

  #----------------------------------------------#

  # EIGEN VALUES FOR TEST DATA AND EIG VECS OF TRAINING DATA

       p <- sum(fea)

   ##!!! have to check if m/n >> p, else there will
   ##    be degeneracy in solution

       test_eigvals <- matrix(,n,p)

       for(i in 1:n)
        {
           test_eigvals[i,] <- eigtest(test[[i]],train[[i]],fea,reg)
        }

      #print(test_eigvals[1])
      #print("Dimension of the matrix of test eigen values")
      #print(dim(test_eigvals))


    #----------------------------------------------------#




  # CREATE RANDOM MATRICES for each Training set and calculate Canonical
   # Correlation

        ran_eig <- array(list(),n) #each matrix here will contain eigvals
                                   # of random matrix generated from
                                   # each train[[i]]

                                   #no of rows = number of iterations

       for(i in 1:n)     # n runs for nfold validation, ie number of train[[i]]
        {

        ran_eig[[i]] <- random_eig(train[[i]],fea,iter,nrow(a)) #subroutine 4.

        }

   # concatenate all ran_eig rowwise and use this matrix for
   # comparison

       random_all <- ran_eig[[1]]
       if(n > 1)
            {
               for( i in 2:n)
               {
                 random_all <- rbind(random_all,ran_eig[[i]])
               }
            }


#-----------------------------------------------------#

  #NOW COMPARE EIGENVALS OF TEST SETS WITH THE EIGVALS OF RANDOM MATRICES
  # take the average of eigen values of all test data sets

        avg_eigs <- apply(test_eigvals,2,mean)


        counts <- comp(avg_eigs,random_all)

        ################################################################
        #Calculating drCCA for given data and returning the projected###
        #data with recommended features(counts)

         cca_data <- gCCA(mat,reg) ##calculating using the function regCCA
         projection <- cca_data$proj
         print(dim(projection))
         proj <- projection[,1:counts]
         return(list(proj=proj, n=counts, cca_data=cca_data, random_all=random_all, avg_eigs=avg_eigs));




}
