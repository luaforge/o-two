#include <OB/CORBA.h>
#include <apptest_impl.h>

//
// IDL:AppTest:1.0
//

//
// IDL:AppTest/Testing:1.0
//
AppTest::Testing_impl::Testing_impl(PortableServer::POA_ptr poa)
    : poa_(PortableServer::POA::_duplicate(poa))
{
}

AppTest::Testing_impl::~Testing_impl()
{
}

PortableServer::POA_ptr
AppTest::Testing_impl::_default_POA()
{
    return PortableServer::POA::_duplicate(poa_);
}

//
// IDL:AppTest/Testing/say:1.0
//
void
AppTest::Testing_impl::say(const char* text)
    throw(CORBA::SystemException)
{
    cout << text << endl;
}
