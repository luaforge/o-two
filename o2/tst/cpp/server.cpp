// **********************************************************************
//
// Copyright (c) 1999
// Object Oriented Concepts, Inc.
// Billerica, MA, USA
//
// All Rights Reserved
//
// **********************************************************************

#include <OB/CORBA.h>

#include <apptest_impl.h>

#include <stdlib.h>
#include <errno.h>

#ifdef HAVE_FSTREAM
#   include <fstream>
#else
#   include <fstream.h>
#endif

#ifdef HAVE_STD_IOSTREAM
using namespace std;
#endif
using namespace AppTest;


int
run(CORBA::ORB_ptr orb, int argc, char* argv[])
{
    //
    // Resolve Root POA
    //
    CORBA::Object_var poaObj = orb -> resolve_initial_references("RootPOA");
    PortableServer::POA_var rootPOA = PortableServer::POA::_narrow(poaObj);
    
    //
    // Get a reference to the POA manager
    //
    PortableServer::POAManager_var manager = rootPOA -> the_POAManager();
    
    //
    // Create implementation object
    //
    Testing_impl* testingImpl = new Testing_impl(rootPOA);
    PortableServer::ServantBase_var servant = testingImpl;
    Testing_var testing = testingImpl->_this();
    
    //
    // Save reference
    //
    CORBA::String_var s = orb->object_to_string(testing);
    
    const char* refFile = "testing.ref";
    ofstream out(refFile);
    if(out.fail())
    {
	cerr << argv[0] << ": can't open `" << refFile << "': "
	     << strerror(errno) << endl;
	return EXIT_FAILURE;
    }

    out << s << endl;
    out.close();
    
    //
    // Run implementation
    //
    manager->activate();
    orb->run();

    return EXIT_SUCCESS;
}

int
main(int argc, char* argv[], char*[])
{
    int status = EXIT_SUCCESS;
    CORBA::ORB_var orb;

    try
    {
	orb = CORBA::ORB_init(argc, argv);
	status = run(orb, argc, argv);
    }
    catch(const CORBA::Exception& ex)
    {
	cerr << ex << endl;
	status = EXIT_FAILURE;
    }

    if(!CORBA::is_nil(orb))
    {
	try
	{
	    orb -> destroy();
	}
	catch(const CORBA::Exception& ex)
	{
	    cerr << ex << endl;
	    status = EXIT_FAILURE;
	}
    }
    
    return status;
}
