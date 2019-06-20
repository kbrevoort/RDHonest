## method assumes X is sorted
## @param J number of nearest neighbors
sigmaNN <- function(X, Y, J=3) {
    n <- length(X)
    sigma2 <- matrix(nrow=n, ncol=NCOL(Y)^2)

    for (k in seq_along(X)) {
        ## d is distance to Jth neighbor, exluding oneself
        s <- max(k-J, 1):k
        d <- sort(abs(c(X[s[-length(s)]], X[k:min(k+J, n)][-1])-X[k]))[J]
        ind <- (abs(X-X[k])<=d)
        ind[k] <- FALSE                 # exclude oneself
        Jk <- sum(ind)
        sigma2[k, ] <- Jk/(Jk+1)*
            if (NCOL(Y)>1)
                as.vector(outer(Y[k, ]-colMeans(Y[ind, ]),
                                Y[k, ]-colMeans(Y[ind, ])))
            else
                (Y[k]-mean(Y[ind]))^2
    }
    drop(sigma2)
}


## Local polynomial regression at a point, normalized to 0
## Calculate estimate of a function at a point and its variance given a
## bandwidth using local polynomial regression of order \code{order}.
## @section Note: Nearest neighbor method assumes data are sorted so that
##     \code{X[i] <= X[i+1]}
## @param Y,X Outcome variable and regressor
## @param h Bandwidth
## @param K Kernel function
## @param order Order of local regression 1 for linear, 2 for quadratic, etc.
## @param sigma2 Optionally, supply estimates of \eqn{\sigma^{2}_{i}} (for
##     \code{"supplied.var"} \code{se.method})
## @template RDse
LPReg <- function(X, Y, h, K, order=1, se.method=NULL, sigma2, J=3) {
    R <- outer(X, 0:order, "^")
    W <- K(X/h)
    Gamma <- crossprod(R, W*R)
    if (sum(W>0) <= order | h==0 |
        class(try(solve(Gamma), silent=TRUE)) != "matrix")
        return(list(theta=0, sigma2=NA, var=NA, w=function(u) 0, eff.obs=0))

    beta <- solve(Gamma, crossprod(R, W*Y))
    ## Squared residuals, allowing for multivariate Y
    sig <- function(r)
        r[, rep(seq_len(ncol(r)), each=ncol(r))] *
        r[, rep(seq_len(ncol(r)), ncol(r))]
    hsigma2 <- sig(Y - R %*% beta)

    ## Robust variance-based formulae
    v <- matrix(nrow=NCOL(hsigma2), ncol=4)
    colnames(v) <- c("supplied.var", "nn", "EHW", "demeaned")
    EHW <- function(sigma2)
        if (NCOL(sigma2)==1)
            sum((W*R %*% solve(Gamma))[, 1]^2 * sigma2)
        else
            colSums((W*R %*% solve(Gamma))[, 1]^2 * sigma2)

    if("EHW" %in% se.method) v[, 3] <- EHW(hsigma2)
    if("supplied.var" %in% se.method) v[, 1] <- EHW(sigma2)
    if("demeaned" %in% se.method) {
        ## Only intercept, return this hsigma2
        hsigma2 <- sig(Y - outer(rep(1, length(X)), beta[1, ]))
        v[, 4] <- EHW(hsigma2)
    }
    if("nn" %in% se.method) {
        hsigma2 <- sigmaNN(X, Y, J=J)
        v[, 2] <- EHW(hsigma2)
    }

    ## weight function if we think of the estimator as linear estimator
    w <- function(x) solve(Gamma, t(outer(x, 0:order, "^")*K(x/h)))[1, ]
    list(theta=beta[1, ], sigma2=hsigma2, var=drop(v),
         w=w, eff.obs=1/sum(w(X)^2))
}


#' Local Polynomial Regression
#'
#' Calculate fuzzy or sharp RD estimate, or estimate of a conditional mean at a
#' point (depending on the class of \code{d}), and its variance using local
#' polynomial regression of order \code{order}.
#'
#' @param d object of class \code{"LPPData"}, \code{"RDData"}, or
#'     \code{"FRDData"}
#' @template RDBW
#' @template Kern
#' @template RDse
#' @param no.warning Don't warn about too few observations
#' @return list with elements:
#'
#' \describe{
#'     \item{estimate}{point estimate}
#'     \item{se}{Named vector of standard error estimates, as specified
#'               by \code{se.method}.}
#'     \item{w}{Implicit weight function used}
#'
#'     \item{sigma2}{Estimate of \eqn{sigma^2(X)} for values of \eqn{X}
#'             receiving positive kernel weight. By default, estimates are based
#'             on squared regression residuals, as used in \code{"EHW"}. If
#'             \code{"demeaned"} or \code{"nn"} is specified, estimates are
#'             based on that method, with \code{"nn"} method used if both are
#'             specified.}
#'
#'      \item{eff.obs}{Number of effective observations}
#'
#' }
#' @examples
#' NPRreg.fit(RDData(lee08, cutoff=0), h=5, order=2, se.method=c("nn", "plugin", "EHW"))
#' NPRreg.fit(LPPData(lee08[lee08$margin>=0, ], point=0), h=5, order=1)
#' d <- FRDData(cbind(logcn=log(rcp[, 6 ]), rcp[, c(3, 2)]), cutoff=0)
#' NPRreg.fit(d, h=10, order=1)
#' @export
NPRreg.fit <- function(d, h, kern="triangular", order=1, se.method="nn",
                       no.warning=FALSE, J=3) {

    K <- if (!is.function(kern)) {
             EqKern(kern, boundary=FALSE, order=0)
         } else {
             kern
         }
    if (inherits(d, "LPPData")) {
        ## Keep only positive kernel weights
        W <- if (h[1]<=0) 0*d$X else K(d$X/h[1]) # kernel weights
        d$X <- d$X[W>0]
    } else {
        if (length(h)==1) h <- c(m=unname(h), p=unname(h))
        Wm <- if (h["m"]<=0) 0*d$Xm else K(d$Xm/h["m"])
        Wp <- if (h["p"]<=0) 0*d$Xp else K(d$Xp/h["p"])
        d$Xp <- d$Xp[Wp>0]
        d$Xm <- d$Xm[Wm>0]
        if(!is.null(d$sigma2p)) d$sigma2p <- as.matrix(d$sigma2p)
        if(!is.null(d$sigma2m)) d$sigma2m <- as.matrix(d$sigma2m)
    }
    nob <- max(length(d$X), min(length(d$Xp), length(d$Xm)))
    uob <- max(length(unique(d$X)),
               min(length(unique(d$Xp)), length(unique(d$Xm))))

    if (nob <= 3*order & no.warning==FALSE)
            warning("Too few observations to compute estimates.\nOnly ",
                    nob, " units with positive weights")
    if (uob <= order & no.warning==FALSE) {
        warning("Too few distinct values to compute estimates.\nOnly ",
                uob, " unique values for ",
                "independent variable with positive weights")
    }

    if (inherits(d, "LPPData")) {
        r <- LPReg(d$X, d$Y[W>0], h[1], K, order, se.method, d$sigma2[W>0], J)
        return(list(estimate=r$theta, se=c(sqrt(r$var), plugin=NA), w=r$w,
                    sigma2=r$sigma2, eff.obs=r$eff.obs))
    }

    rm <- LPReg(d$Xm, as.matrix(d$Ym)[Wm>0, ], h["m"], K, order, se.method,
                d$sigma2m[Wm>0, ], J)
    rp <- LPReg(d$Xp, as.matrix(d$Yp)[Wp>0, ], h["p"], K, order, se.method,
                d$sigma2p[Wp>0, ], J)
    ret <- list(estimate=NULL, se=NULL, wm=rm$w, wp=rp$w, sigma2m=rm$sigma2,
                sigma2p=rp$sigma2, eff.obs=rm$eff.obs+rp$eff.obs)
    if (inherits(d, "RDData")) {
        plugin <- NA
        if ("plugin" %in% se.method) {
            if (is.function(kern)) {
                ke <- EqKern(kern, boundary=TRUE, order=order)
                nu0 <- KernMoment(ke, moment=0, boundary=TRUE, "raw2")
            } else {
                nu0 <- RDHonest::kernC[RDHonest::kernC$kernel==kern &
                                       RDHonest::kernC$order==order &
                                       RDHonest::kernC$boundary==TRUE, "nu0"]
            }
            ## we kept original outcomes, but only kept X's receiving positive
            ## weight
            N <- length(d$Yp) + length(d$Ym)
            f0 <- sum(length(d$Xp)+length(d$Xm)) / (N*(h[1]+h[2]))
            plugin <- nu0 * (mean(rp$sigma2)/h["p"] +
                             mean(rm$sigma2)/h["m"]) / (N*f0)
        }
        ret$estimate <- rp$theta-rm$theta
        ret$se <- sqrt(c(rm$var+rp$var, plugin=plugin))
    } else if (inherits(d, "FRDData")) {
        ret$fs <- rp$theta[2]-rm$theta[2]
        ret$estimate <- (rp$theta[1]-rm$theta[1]) / ret$fs
        ret$se <- c(sqrt(drop(t(rp$var+rm$var) %*%
                              c(1, -ret$estimate, -ret$estimate, ret$estimate^2)
                              ) / ret$fs^2),
                    plugin=NA)
    }
    ret
}


NPRPrelimVar.fit <- function(d, se.initial="EHW") {
    if (se.initial == "NN") {
        if (inherits(d, "LPPData")) {
            d$sigma2 <- sigmaNN(d$X, d$Y, J=3)
        } else {
            d$sigma2p <- sigmaNN(d$Xp, d$Yp, J=3)
            d$sigma2m <- sigmaNN(d$Xm, d$Ym, J=3)
        }
        return(d)
    }
    ## Pilot bandwidth: either IK/ROT, or else Silverman for uniform kernel,
    ## making sure this results in enough distinct values on either side of
    ## threshold
    if (se.initial == "EHW" | se.initial == "demeaned") {
        drf <- d
        ## Use reduced form for FRD
        if (inherits(d, "FRDData")) {
            drf$Yp <- drf$Yp[, 1]
            drf$Ym <- drf$Ym[, 1]
        }
        h1 <- if (inherits(d, "LPPData")) ROTBW.fit(drf) else IKBW.fit(drf)
    } else if (se.initial == "Silverman" | se.initial == "SilvermanNN") {
        X <- if (inherits(d, "LPPData")) d$X else c(d$Xm, d$Xp)
        Xmin <- if (inherits(d, "LPPData")) {
                    sort(abs(unique(d$X)))[2]
                } else  {
                    max(sort(unique(d$Xp))[2], sort(abs(unique(d$Xm)))[2])
                }
        h1 <- max(1.84*stats::sd(X)/sum(length(X))^(1/5), Xmin)
    }

    if (se.initial=="Silverman") {
        r1 <- NPRreg.fit(d=d, h=h1, kern="uniform", order=0, se.method="EHW")
        ## Variance adjustment for backward compatibility
        if (inherits(d, "LPPData")) {
            r1$sigma2 <- r1$sigma2*length(r1$sigma2) / (length(r1$sigma2)-1)
        } else {
            r1$sigma2p <- r1$sigma2p*length(r1$sigma2p) / (length(r1$sigma2p)-1)
            r1$sigma2m <- r1$sigma2m*length(r1$sigma2m) / (length(r1$sigma2m)-1)
        }
    } else if (se.initial=="SilvermanNN") {
        r1 <- NPRreg.fit(d=d, h=h1, kern="uniform", order=1, se.method="nn")
    } else if (se.initial == "EHW" | se.initial == "demeaned") {
        r1 <- NPRreg.fit(d, h1, se.method=se.initial)
    } else {
        stop("Unknown method for estimating initial variance")
    }

    if (inherits(d, "LPPData")) {
        d$sigma2 <- rep(mean(r1$sigma2), length(d$X))
    } else if (inherits(d, "RDData")) {
        d$sigma2p <- rep(mean(r1$sigma2p), length(d$Xp))
        d$sigma2m <- rep(mean(r1$sigma2m), length(d$Xm))
    } else {
        d$sigma2m <- matrix(rep(colMeans(r1$sigma2m), each=length(d$Xm)),
                                nrow=length(d$Xm))
        d$sigma2p <- matrix(rep(colMeans(r1$sigma2p), each=length(d$Xp)),
                            nrow=length(d$Xp))
    }
    d
}

#' Rule of thumb for choosing M
#'
#' Use global quartic regression to estimate a bound on the second derivative
#' for inference under under second order Hölder class. For RD, use a separate
#' regression on either side of the cutoff
#'
#' @param d object of class \code{"RDData"}
#' @examples
#' NPR_MROT.fit(RDData(lee08, cutoff=0))
#' NPR_MROT.fit(LPPData(lee08[lee08$margin>0, ], point=0))
#' d <- FRDData(cbind(logcn=log(rcp[, 6 ]), rcp[, c(3, 2)]), cutoff=0)
#' NPR_MROT.fit(d)
#' @export
NPR_MROT.fit <- function(d) {
    if (inherits(d, "RDData")) {
        max(NPR_MROT.fit(LPPData(data.frame(Y=d$Yp, X=d$Xp), 0)),
            NPR_MROT.fit(LPPData(data.frame(Y=d$Ym, X=d$Xm), 0)))
    } else if (inherits(d, "FRDData")) {
        c(M1=max(NPR_MROT.fit(LPPData(data.frame(Y=d$Yp[, 1], X=d$Xp), 0)),
                 NPR_MROT.fit(LPPData(data.frame(Y=d$Ym[, 1], X=d$Xm), 0))),
          M2=max(NPR_MROT.fit(LPPData(data.frame(Y=d$Yp[, 2], X=d$Xp), 0)),
                 NPR_MROT.fit(LPPData(data.frame(Y=d$Ym[, 2], X=d$Xm), 0))))
    } else if (inherits(d, "LPPData")) {
        ## STEP 1: Estimate global polynomial regression
        r1 <- unname(stats::lm(d$Y ~ 0 + outer(d$X, 0:4, "^"))$coefficients)
        f2 <- function(x) abs(2*r1[3]+6*x*r1[4]+12*x^2*r1[5])
        ## maximum occurs either at endpoints, or else at the extremum,
        ## -r1[4]/(4*r1[5]), if the extremum is in the support
        f2e <- -r1[4]/(4*r1[5])
        M <- max(f2(min(d$X)), f2(max(d$X)))
        if (min(d$X) < f2e & max(d$X) > f2e) M <- max(f2(f2e), M)

        M
    }
}