// A C-callable front-end to the AGS global-optimization library.
//  -- Vladislav Sovrasov

#include "ags.h"
#include "solver.hpp"
#include <iostream>

double ags_r = 3;
double eps_res = 0.001;
unsigned evolvent_density = 12;
int ags_verbose = 0;

int ags_minimize(unsigned n, nlopt_func func, void *data, unsigned m, nlopt_constraint *fc,
                 double *x, double *minf, const double *l, const double *u, nlopt_stopping *stop)
{
	int ret_code = NLOPT_SUCCESS;

	if (n > ags::solverMaxDim)
		return NLOPT_INVALID_ARGS;
	if(m != nlopt_count_constraints(m, fc) || m > ags::solverMaxConstraints)
		return NLOPT_INVALID_ARGS;

	std::vector<double> lb(l, l + n);
	std::vector<double> ub(u, u + n);
	std::vector<ags::NLPSolver::FuncPtr> functions;
	for (unsigned i = 0; i < m; i++)
	{
		if (fc[i].m != 1)
			return NLOPT_INVALID_ARGS;
		functions.push_back([fc, data, n, i](const double* x) {return fc[i].f(n, x, NULL, data);});
	}
	functions.push_back([func, data, n](const double* x) {return func(n, x, NULL, data);});

	ags::SolverParameters params;
	params.r = ags_r;
	params.itersLimit = stop->maxeval;
	params.eps = 1e-64;
	params.evolventDensity = evolvent_density;
	params.epsR = eps_res;

	ags::NLPSolver solver;
	solver.SetParameters(params);
	solver.SetProblem(functions, lb, ub);

	ags::Trial optPoint;
	try
	{
		optPoint = solver.Solve();
	}
	catch (const std::runtime_error& exp)
	{
		std::cerr << "AGS internal error: " << std::string(exp.what()) << std::endl;
		return NLOPT_FAILURE;
	}

	if (ags_verbose)
	{
    auto calcCounters = solver.GetCalculationsStatistics();
    auto holderConstEstimations = solver.GetHolderConstantsEstimations();

    std::cout << std::string(20, '-') << "AGS statistics: " << std::string(20, '-') << std::endl;
    for (size_t i = 0; i < calcCounters.size() - 1; i++)
      std::cout << "Number of calculations of constraint # " << i << ": " << calcCounters[i] << "\n";
    std::cout << "Number of calculations of objective: " << calcCounters.back() << "\n";;

    for (size_t i = 0; i < holderConstEstimations.size() - 1; i++)
      std::cout << "Estimation of Holder constant of function # " << i << ": " << holderConstEstimations[i] << "\n";
    std::cout << "Estimation of Holder constant of objective: " << holderConstEstimations.back() << "\n";
    if (optPoint.idx != m)
      std::cout << "Feasible point not found" << "\n";
    std::cout << std::string(40, '-') << std::endl;
	}

	if (m == optPoint.idx)
	{
		memcpy(x, optPoint.y, n*sizeof(x[0]));
		*minf = optPoint.g[optPoint.idx];
	}
	else //feasible point not found.
		return NLOPT_FAILURE;

	if (solver.GetCalculationsStatistics()[0] >= params.itersLimit)
		return NLOPT_MAXEVAL_REACHED;

  return ret_code;
}
