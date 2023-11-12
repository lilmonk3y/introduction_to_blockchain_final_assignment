// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

// No estoy seguro si nos sirve porque pareciera tener solo ecuaciones de una variable
import "https://github.com/bandprotocol/contracts/blob/master/contracts/utils/Equation.sol";

/*
    Este contrato almacena problemas matemáticos para los cuales asocia recompensas. Si un interesado en dicha recompensa
    encuentra una solución para el problema, debe publicar el punto en el cual cree que está la solución y el contrato
    lo verificará. Si es correcta se le paga el premio.
*/
contract Name {
    // types
    type ProblemId is int64;

    type PaymentCommitment is int64;

    struct Problem {
        Equation body;
        PaymentCommitment commitment;
        // si un problema se quita de los publicados le debemos devolver su compromiso económico a quien lo publicó.
        address publisher;
    }

    // private members 
    mapping(ProblemId => Problem) problems;

    // TODO
    function publishProblem(string calldata problem, PaymentCommitment commitment) external  returns (ProblemId);

    function verifySolution(ProblemId problem, int64[] point) external;

    function serializeProblem(string calldata problem) private returns (Equation);

    function unpublishProblem(ProblemId problem) external returns (bool);
}